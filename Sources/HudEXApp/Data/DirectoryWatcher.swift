import CoreServices
import Foundation

/// Event-driven directory watcher built on FSEvents.
///
/// Watching the *directory* rather than the file is deliberate: OneDrive,
/// Obsidian and editors commonly write a temporary file and rename it over the
/// target, which would leave a watcher bound to the old inode pointing at
/// nothing. FSEvents reports the directory change instead, and the caller
/// re-reads the file only when its signature actually changed.
final class DirectoryWatcher {
    private let queue = DispatchQueue(label: "dev.hex.hudex.watcher", qos: .utility)
    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?

    /// Directory currently being watched.
    private(set) var directory: URL?
    /// Only events whose path has this last path component trigger the callback.
    private(set) var fileName: String?

    /// Called on the watcher queue after the debounce window.
    var onChanges: (() -> Void)?

    deinit {
        stop()
    }

    var isRunning: Bool { stream != nil }

    /// Starts watching `directory` for changes to `fileName`.
    @discardableResult
    func start(directory: URL, fileName: String, debounce: TimeInterval = 0.35) -> Bool {
        stop()
        self.directory = directory
        self.fileName = fileName

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagWatchRoot
        )

        let callback: FSEventStreamCallback = { _, info, eventCount, eventPaths, eventFlags, _ in
            guard let info else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.handleEvents(
                count: Int(eventCount),
                paths: eventPaths,
                flags: eventFlags
            )
        }

        let paths = [directory.path] as CFArray
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            flags
        ) else {
            Log.watcher.error("FSEventStreamCreate failed for \(directory.path, privacy: .public)")
            self.directory = nil
            self.fileName = nil
            return false
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            Log.watcher.error("FSEventStreamStart failed for \(directory.path, privacy: .public)")
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            return false
        }

        Log.debug(Log.watcher, "watching \(directory.path)")
        return true
    }

    func stop() {
        pending?.cancel()
        pending = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        directory = nil
        fileName = nil
    }

    // MARK: - Callback

    private func handleEvents(count: Int, paths: UnsafeMutableRawPointer, flags: UnsafePointer<FSEventStreamEventFlags>) {
        let pathArray = paths.assumingMemoryBound(to: UnsafePointer<CChar>?.self)
        var relevant = false
        let wanted = fileName

        for index in 0..<count {
            let eventFlags = flags[index]
            // A directory-level event (rename of the watched folder, journal
            // wrap) can hide a change to our file: always treat it as relevant.
            let isDirectoryLevel = eventFlags & FSEventStreamEventFlags(
                kFSEventStreamEventFlagMustScanSubDirs
                    | kFSEventStreamEventFlagRootChanged
                    | kFSEventStreamEventFlagEventIdsWrapped
                    | kFSEventStreamEventFlagKernelDropped
                    | kFSEventStreamEventFlagUserDropped
            ) != 0
            if isDirectoryLevel {
                relevant = true
                continue
            }
            guard let wanted else {
                relevant = true
                continue
            }
            guard let cPath = pathArray[index] else { continue }
            let path = String(cString: cPath)
            if (path as NSString).lastPathComponent == wanted {
                relevant = true
            }
        }

        guard relevant else { return }
        scheduleDebouncedSignal()
    }

    private func scheduleDebouncedSignal() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.stream != nil else { return }
            self.onChanges?()
        }
        pending = work
        queue.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// Nearest existing ancestor of `url`, which is what can actually be
    /// watched when the target folder has not been created or synced yet.
    static func nearestExistingDirectory(for url: URL, fileManager: FileManager = .default) -> URL? {
        var candidate = url.deletingLastPathComponent().standardizedFileURL
        while candidate.path != "/" {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return candidate
            }
            candidate = candidate.deletingLastPathComponent().standardizedFileURL
        }
        return fileManager.fileExists(atPath: "/") ? URL(fileURLWithPath: "/") : nil
    }
}
