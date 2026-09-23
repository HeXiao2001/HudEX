import Foundation
import HudEXCore

/// Owns the parsed document: loads it off the main thread, watches the source
/// directory, and publishes a new immutable value only when something actually
/// changed.
///
/// Reliability rules implemented here:
/// * a failed load never clears what is on screen — the last good document
///   stays until a new parse succeeds;
/// * the file is only read when its signature (mtime + size + id) changed;
/// * the directory is watched, so atomic replace/rename keeps working.
@MainActor
final class DocumentStore: ObservableObject {
    enum SynchronizedWriteResult {
        case written
        case unchanged
        case failed(String)
    }

    @Published private(set) var document: HudEXDocument = .empty
    @Published private(set) var sourceURL: URL?
    @Published private(set) var statusMessage: String?
    @Published private(set) var lastError: String?
    @Published private(set) var lastLoadedAt: Date?
    @Published private(set) var isLoading = false
    /// Bumped every time a load attempt finishes, successful or not, so startup
    /// can wait for a real answer instead of guessing with a timer.
    @Published private(set) var loadAttempts = 0

    /// Fired after `document` changes, so the layout layer can rebuild.
    var onDocumentChanged: (() -> Void)?

    private let loader = MarkdownDocumentLoader()
    private let watcher = DirectoryWatcher()
    private let loadQueue = DispatchQueue(label: "dev.hex.hudex.loader", qos: .utility)
    private var signature: FileSignature?
    private var loadGeneration = 0
    /// True while a "the file is empty right now" read is being double-checked.
    private var isEmptyRetryPending = false

    init() {
        watcher.onChanges = { [weak self] in
            Task { @MainActor in
                self?.reloadIfChanged(reason: "file system event")
            }
        }
    }

    // MARK: - Lifecycle

    func start(url: URL) {
        configureSource(url)
        reload(reason: "startup")
    }

    func stop() {
        watcher.stop()
    }

    /// Points the store at a new file and rewatches.
    func configureSource(_ url: URL) {
        guard sourceURL != url else { return }
        sourceURL = url
        signature = nil
        restartWatcher(for: url)
        reload(reason: "source changed")
    }

    /// Forces a re-read, ignoring the signature cache.
    func reload(reason: String) {
        guard let sourceURL else { return }
        signature = nil
        load(url: sourceURL, reason: reason)
    }

    /// Cheap re-read: only touches disk when the file signature changed.
    func reloadIfChanged(reason: String) {
        guard let sourceURL else { return }
        load(url: sourceURL, reason: reason)
    }

    /// Writes an EventKit reconciliation back to a JSON source and reloads it
    /// through the normal file-watching path.
    @discardableResult
    func saveSynchronizedJSON(_ updated: HudEXDocument) -> SynchronizedWriteResult {
        guard updated.format == .json, let sourceURL else {
            return .failed("The current source is not a writable JSON file.")
        }
        do {
            let data = try HudEXJSONCodec.encode(updated)
            guard (try? Data(contentsOf: sourceURL)) != data else { return .unchanged }
            try data.write(to: sourceURL, options: .atomic)
            signature = nil
            reload(reason: "Reminders sync")
            return .written
        } catch {
            lastError = error.localizedDescription
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Loading

    private func load(url: URL, reason: String) {
        isLoading = true
        loadGeneration += 1
        let generation = loadGeneration
        let previous = signature
        let now = Date()

        loadQueue.async { [loader] in
            let result = loader.load(url: url, previous: previous, now: now)
            Task { @MainActor in
                self.apply(result, generation: generation, reason: reason)
            }
        }
    }

    private func apply(
        _ result: Result<LoadedDocument, DocumentLoadError>,
        generation: Int,
        reason: String
    ) {
        guard generation == loadGeneration else { return }   // superseded
        isLoading = false

        switch result {
        case .success(let loaded):
            signature = loaded.signature

            // A file that is momentarily empty is normally an editor or sync
            // client truncating before it writes. Keep the last good document
            // on screen and re-read once; if it is still empty, the user really
            // did empty the file and the tabs go away.
            if loaded.document.projects.isEmpty, !document.projects.isEmpty, !isEmptyRetryPending {
                isEmptyRetryPending = true
                statusMessage = L10n.t("error.emptyDocument")
                Log.markdown.warning("empty document read; keeping the last good content (\(reason))")
                scheduleForcedReload(after: 3)
                return
            }
            isEmptyRetryPending = false

            lastLoadedAt = loaded.document.parsedAt
            lastError = nil
            statusMessage = nil
            if loaded.document != document {
                document = loaded.document
                onDocumentChanged?()
            }
            Log.debug(Log.markdown, "loaded \(loaded.document.projects.count) projects (\(reason))")

        case .failure(.unchanged):
            // Nothing new to read: the previous attempt already counted.
            return

        case .failure(let error):
            if case .fileMissing = error {
                statusMessage = error.displayMessage
            } else {
                lastError = error.displayMessage
            }
            Log.markdown.warning("load failed: \(error.displayMessage, privacy: .public)")
        }
        loadAttempts += 1
    }

    /// One deferred re-read after a transient empty file. Bounded: at most one
    /// extra read per event, and none of it repeats.
    private func scheduleForcedReload(after delay: TimeInterval) {
        guard let sourceURL else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isEmptyRetryPending else { return }
            self.signature = nil
            self.load(url: sourceURL, reason: "empty-document re-check")
        }
    }

    // MARK: - Watching

    private func restartWatcher(for url: URL) {
        guard let directory = DirectoryWatcher.nearestExistingDirectory(for: url) else {
            watcher.stop()
            return
        }
        watcher.start(directory: directory, fileName: url.lastPathComponent)
    }

    /// Re-arms the watcher when the source folder appears later (OneDrive still
    /// syncing, a Drive mount, a newly created folder).
    func rearmWatcherIfNeeded() {
        guard let sourceURL else { return }
        let expected = DirectoryWatcher.nearestExistingDirectory(for: sourceURL)
        if watcher.directory != expected || !watcher.isRunning {
            restartWatcher(for: sourceURL)
        }
    }
}
