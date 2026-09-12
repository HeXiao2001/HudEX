import Foundation

/// A project's state as written in `HudEX.md`.
///
/// Only the states that HudEX itself understands are enumerated. Anything
/// unrecognised stays `.unknown` and keeps its raw text, so the file remains
/// human-owned: HudEX never asks the author to write a "valid" status.
public enum ProjectStatus: String, Sendable, CaseIterable, Hashable {
    case active
    case paused
    case archived
    case done
    case unknown

    /// Recognised status words (Chinese and English), matched case-insensitively.
    private static let aliases: [String: ProjectStatus] = [
        "进行中": .active,
        "进行": .active,
        "活跃": .active,
        "active": .active,
        "in progress": .active,
        "inprogress": .active,
        "wip": .active,
        "暂停": .paused,
        "搁置": .paused,
        "挂起": .paused,
        "paused": .paused,
        "on hold": .paused,
        "归档": .archived,
        "存档": .archived,
        "archived": .archived,
        "完成": .done,
        "已完成": .done,
        "done": .done,
        "complete": .done,
        "completed": .done
    ]

    /// Parses a raw status string. Never fails: unknown text yields `.unknown`.
    public static func parse(_ raw: String) -> ProjectStatus {
        let key = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !key.isEmpty else { return .unknown }
        if let exact = aliases[key] { return exact }
        // Tolerate decoration such as "进行中（主攻）" or "state: paused".
        // Longest alias first so that ordered iteration stays deterministic.
        for alias in aliases.keys.sorted(by: { $0.count > $1.count }) where key.contains(alias) {
            return aliases[alias] ?? .unknown
        }
        return .unknown
    }

    /// Short human-readable label used by the detail window.
    public var displayName: String {
        switch self {
        case .active: return "进行中"
        case .paused: return "暂停"
        case .archived: return "归档"
        case .done: return "已完成"
        case .unknown: return "未标注"
        }
    }
}

/// One `### section` inside a project.
///
/// HudEX deliberately has a single section type: "当前", "下一步", "备注" and
/// any custom `###` heading are all just sections. A few semantic lookups are
/// offered as helpers instead of separate model types.
public struct ProjectSection: Identifiable, Hashable, Sendable {
    /// Stable within a project: derived from the heading text.
    public let id: String
    /// Heading text exactly as written (without the leading `###`).
    public let title: String
    /// Raw Markdown body of the section.
    public let body: String

    public init(id: String, title: String, body: String) {
        self.id = id
        self.title = title
        self.body = body
    }

    public var isEmpty: Bool {
        body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Normalised heading used for semantic matching.
    var normalizedTitle: String {
        SectionKind.normalize(title)
    }
}

/// The section headings HudEX gives special meaning to, plus everything else.
public enum SectionKind: String, Sendable, CaseIterable {
    case current
    case next
    case latestConversation
    case notes

    private static let aliases: [SectionKind: [String]] = [
        .current: ["当前", "现在", "当前进展", "进展", "current", "now", "status"],
        .next: ["下一步", "接下来", "后续", "计划", "next", "next steps", "nextsteps", "todo"],
        .latestConversation: ["最新对话", "最近对话", "最新聊天", "对话", "latest conversation", "latest chat", "conversation"],
        .notes: ["备注", "注", "说明", "notes", "note", "remarks"]
    ]

    public var displayName: String {
        switch self {
        case .current: return "当前"
        case .next: return "下一步"
        case .latestConversation: return "最新对话"
        case .notes: return "备注"
        }
    }

    static func normalize(_ title: String) -> String {
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while text.hasSuffix(":") || text.hasSuffix("：") {
            text.removeLast()
            text = text.trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    static func match(_ title: String) -> SectionKind? {
        let key = normalize(title)
        guard !key.isEmpty else { return nil }
        for kind in SectionKind.allCases {
            let candidates = aliases[kind] ?? []
            if candidates.contains(key) { return kind }
        }
        return nil
    }
}

/// One project: a `## heading` in `HudEX.md`.
public struct HudEXProject: Identifiable, Hashable, Sendable {
    /// Stable across reloads so views and panels never churn on re-parse.
    public let id: String
    /// Full project name (`## heading`).
    public let title: String
    /// Explicit `短名：` when present, otherwise a derived abbreviation.
    public let shortTitle: String
    /// True when `短名：` was written by hand in the file.
    public let hasExplicitShortTitle: Bool
    public let status: ProjectStatus
    /// Raw `状态：` text, for the detail window.
    public let statusText: String?
    public let updatedAt: Date?
    /// Raw `更新：` text, shown even when it cannot be parsed as a date.
    public let updatedAtText: String?
    /// Prose found between the project heading and its first section.
    public let preamble: String?
    public let sections: [ProjectSection]

    public init(
        id: String,
        title: String,
        shortTitle: String,
        hasExplicitShortTitle: Bool,
        status: ProjectStatus,
        statusText: String?,
        updatedAt: Date?,
        updatedAtText: String?,
        preamble: String?,
        sections: [ProjectSection]
    ) {
        self.id = id
        self.title = title
        self.shortTitle = shortTitle
        self.hasExplicitShortTitle = hasExplicitShortTitle
        self.status = status
        self.statusText = statusText
        self.updatedAt = updatedAt
        self.updatedAtText = updatedAtText
        self.preamble = preamble
        self.sections = sections
    }

    // MARK: - Semantic section helpers

    public func section(_ kind: SectionKind) -> ProjectSection? {
        sections.first { SectionKind.match($0.title) == kind }
    }

    public var currentSection: ProjectSection? { section(.current) }
    public var nextSection: ProjectSection? { section(.next) }
    public var latestConversationSection: ProjectSection? { section(.latestConversation) }
    public var notesSection: ProjectSection? { section(.notes) }

    /// The sections shown in the hover preview, in reading order.
    public var previewSections: [ProjectSection] {
        [currentSection, nextSection, latestConversationSection].compactMap { $0 }
    }

    /// Sections that are not one of the built-in kinds. They still render
    /// normally in the detail window.
    public var customSections: [ProjectSection] {
        sections.filter { SectionKind.match($0.title) == nil }
    }

    /// `状态：` line for the detail window; falls back to the parsed status.
    public var statusDisplayText: String {
        if let statusText, !statusText.isEmpty { return statusText }
        return status == .unknown ? "—" : status.displayName
    }
}

/// One diagnostic produced while reading `HudEX.md`.
public struct ParseDiagnostic: Hashable, Sendable {
    public enum Severity: String, Sendable {
        case info
        case warning
        case error
    }

    public let severity: Severity
    public let message: String
    /// 1-based line number when the diagnostic points at a specific line.
    public let line: Int?

    public init(severity: Severity, message: String, line: Int? = nil) {
        self.severity = severity
        self.message = message
        self.line = line
    }
}

/// The parsed contents of `HudEX.md`.
///
/// A document is an immutable value: a successful parse replaces the previous
/// one atomically, and a failed parse keeps the last good document on screen.
public struct HudEXDocument: Hashable, Sendable {
    public var title: String?
    public var projects: [HudEXProject]
    public var diagnostics: [ParseDiagnostic]
    /// When the file was parsed.
    public var parsedAt: Date
    /// Modification date of the source file, used as an age fallback when a
    /// project has no parsable `更新：`.
    public var fileModifiedAt: Date?

    public init(
        title: String? = nil,
        projects: [HudEXProject] = [],
        diagnostics: [ParseDiagnostic] = [],
        parsedAt: Date = Date(),
        fileModifiedAt: Date? = nil
    ) {
        self.title = title
        self.projects = projects
        self.diagnostics = diagnostics
        self.parsedAt = parsedAt
        self.fileModifiedAt = fileModifiedAt
    }

    public static let empty = HudEXDocument(parsedAt: .distantPast)

    public var isEmpty: Bool { projects.isEmpty }

    public func project(id: String) -> HudEXProject? {
        projects.first { $0.id == id }
    }

    /// Effective timestamp used to colour a tag: the project's own `更新：`
    /// when parsable, otherwise the file's modification date.
    public func ageReferenceDate(for project: HudEXProject) -> Date? {
        project.updatedAt ?? fileModifiedAt
    }
}
