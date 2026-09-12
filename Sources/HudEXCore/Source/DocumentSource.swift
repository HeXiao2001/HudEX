import Foundation

/// Cheap identity of the watched file, used to decide whether a file system
/// event actually changed anything.
///
/// `modificationDate` + size + file id catches the OneDrive/Obsidian pattern of
/// writing a temporary file and renaming it over the original, where a naive
/// inode watch would silently stop working.
public struct FileSignature: Equatable, Sendable {
    public var url: URL
    public var modificationDate: Date?
    public var size: Int?
    public var fileIdentifier: String?
    public var exists: Bool

    public init(
        url: URL,
        modificationDate: Date?,
        size: Int?,
        fileIdentifier: String?,
        exists: Bool
    ) {
        self.url = url
        self.modificationDate = modificationDate
        self.size = size
        self.fileIdentifier = fileIdentifier
        self.exists = exists
    }

    public static let missing = FileSignature(
        url: URL(fileURLWithPath: "/"),
        modificationDate: nil,
        size: nil,
        fileIdentifier: nil,
        exists: false
    )

    /// Reads the signature with a single `stat`-level query; never reads the
    /// file contents.
    ///
    /// `FileManager.attributesOfItem` is used rather than
    /// `URL.resourceValues(forKeys:)` because the URL variant caches its
    /// resource values per URL instance — a cache that silently hides exactly
    /// the change this type exists to detect.
    public static func read(at url: URL) -> FileSignature {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return FileSignature(
                url: url,
                modificationDate: nil,
                size: nil,
                fileIdentifier: nil,
                exists: false
            )
        }
        let type = attributes[.type] as? FileAttributeType
        let size = (attributes[.size] as? NSNumber)?.intValue
        let identifier = (attributes[.systemFileNumber] as? NSNumber)?.stringValue
        return FileSignature(
            url: url,
            modificationDate: attributes[.modificationDate] as? Date,
            size: size,
            fileIdentifier: identifier,
            exists: type == .typeRegular || size != nil
        )
    }
}

/// A parsed document plus the signature it was parsed from.
public struct LoadedDocument: Sendable {
    public var document: HudEXDocument
    public var signature: FileSignature
    public var text: String

    public init(document: HudEXDocument, signature: FileSignature, text: String) {
        self.document = document
        self.signature = signature
        self.text = text
    }
}

/// Failure modes when reading `HudEX.md`. None of them is fatal: the previous
/// document stays on screen.
public enum DocumentLoadError: Error, Equatable {
    case fileMissing(URL)
    case unreadable(URL, String)
    case undecodable(URL)
    case tooLarge(URL, Int)
    case unchanged

    public var displayMessage: String {
        switch self {
        case .fileMissing(let url):
            return L10n.t("error.fileMissing", url.path)
        case .unreadable(_, let reason):
            return L10n.t("error.unreadable", reason)
        case .undecodable(let url):
            return L10n.t("error.undecodable", url.lastPathComponent)
        case .tooLarge(_, let size):
            return L10n.t("error.tooLarge", size / 1024)
        case .unchanged:
            return L10n.t("error.unchanged")
        }
    }
}

/// Reads and parses `HudEX.md`.
///
/// Runs off the main thread; the caller publishes the result on the main actor.
public struct MarkdownDocumentLoader: Sendable {
    /// Files larger than this are ignored rather than loaded: a project context
    /// file has no business being megabytes long.
    public static let maximumBytes = 4 * 1024 * 1024

    private let parser: MarkdownProjectParser

    public init(parser: MarkdownProjectParser = MarkdownProjectParser()) {
        self.parser = parser
    }

    /// Loads the document if `signature` differs from `previous`.
    public func load(
        url: URL,
        previous: FileSignature?,
        now: Date = Date()
    ) -> Result<LoadedDocument, DocumentLoadError> {
        let signature = FileSignature.read(at: url)
        guard signature.exists else {
            return .failure(.fileMissing(url))
        }
        if let previous, previous == signature {
            return .failure(.unchanged)
        }
        if let size = signature.size, size > Self.maximumBytes {
            return .failure(.tooLarge(url, size))
        }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            return .failure(.unreadable(url, error.localizedDescription))
        }

        guard let text = Self.decode(data) else {
            return .failure(.undecodable(url))
        }

        let document = parser.parse(text, fileModifiedAt: signature.modificationDate, now: now)
        return .success(LoadedDocument(document: document, signature: signature, text: text))
    }

    /// UTF-8 first (Obsidian, OneDrive, git and every modern editor write
    /// UTF-8), then GB18030 for legacy Chinese files, then Latin-1 so that
    /// nothing ever hard-fails.
    ///
    /// UTF-16 is only attempted when a byte-order mark is present: almost any
    /// even-length byte sequence decodes as UTF-16, which would otherwise turn
    /// a readable file into mojibake.
    public static func decode(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            if let text = String(data: data, encoding: .utf16) { return text }
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: Self.gb18030) { return text }
        if let text = String(data: data, encoding: .isoLatin1) { return text }
        return nil
    }

    /// GB18030 is not exposed as a `String.Encoding` constant.
    private static let gb18030 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
    )
}

/// Resolves which `HudEX.md` to use when the user has not chosen one yet.
public enum SourceLocator {
    /// Candidate locations, in priority order.
    public static func candidates(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        cloudStorageRoot: URL? = nil
    ) -> [URL] {
        var urls: [URL] = [
            homeDirectory.appendingPathComponent("Documents/HudEX.md")
        ]

        // OneDrive (and other File Provider locations) live under
        // ~/Library/CloudStorage on modern macOS. HudEX only reads the local
        // synced copy; the OneDrive client owns the network side.
        let cloudRoot = cloudStorageRoot
            ?? homeDirectory.appendingPathComponent("Library/CloudStorage")
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: cloudRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                urls.append(entry.appendingPathComponent("HudEX.md"))
            }
        }

        urls.append(homeDirectory.appendingPathComponent("Desktop/HudEX.md"))
        return urls
    }

    /// First candidate that exists, otherwise `nil`.
    public static func firstExisting(candidates: [URL]) -> URL? {
        candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Expands a stored path (`~` included) into a file URL.
    public static func url(forStoredPath path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL
    }
}
