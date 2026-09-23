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

    /// Localised label used by the detail window.
    public var displayName: String { L10n.t(displayNameKey) }

    public var displayNameKey: String {
        switch self {
        case .active: return "status.active"
        case .paused: return "status.paused"
        case .archived: return "status.archived"
        case .done: return "status.done"
        case .unknown: return "status.unknown"
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

/// A task mirrored between the structured project file and Apple Reminders.
public struct HudEXReminder: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var notes: String?
    public var dueDate: Date?
    public var isCompleted: Bool
    public var priority: Int
    public var reminderIdentifier: String?
    public var modifiedAt: Date?
    public var syncFingerprint: String?

    public init(
        id: String = UUID().uuidString.lowercased(),
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        priority: Int = 0,
        reminderIdentifier: String? = nil,
        modifiedAt: Date? = nil,
        syncFingerprint: String? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.priority = priority
        self.reminderIdentifier = reminderIdentifier
        self.modifiedAt = modifiedAt
        self.syncFingerprint = syncFingerprint
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

    public static func match(_ title: String) -> SectionKind? {
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
    /// Optional `顺序：` — a smaller number is shown first.
    public let sortOrder: Int?
    /// Optional `颜色：` — a palette name or `#RRGGBB`.
    public let colorOverride: String?
    /// Optional `优先级：` — drawn as the colour of the tag's punched hole.
    public let priority: ProjectPriority?
    public let reminders: [HudEXReminder]

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
        sections: [ProjectSection],
        sortOrder: Int? = nil,
        colorOverride: String? = nil,
        priority: ProjectPriority? = nil,
        reminders: [HudEXReminder] = []
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
        self.sortOrder = sortOrder
        self.colorOverride = colorOverride
        self.priority = priority
        self.reminders = reminders
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
        return status.displayName
    }
}

/// The `# HudEX 设置` block at the bottom of the file.
///
/// HudEX keeps its own settings there in a human- and AI-editable form and
/// syncs them in both directions: edit a value in the file and HudEX applies
/// it; change a setting in the app and HudEX writes it back.
public struct HudEXSettingsBlock: Sendable, Equatable, Hashable {
    public struct Entry: Sendable, Equatable, Hashable {
        /// Stable ASCII key, e.g. `layout.mode`.
        public let key: String
        /// Value exactly as written.
        public var value: String
        /// The guide line above the entry, without the leading `> `.
        public var guide: String?

        public init(key: String, value: String, guide: String? = nil) {
            self.key = key
            self.value = value
            self.guide = guide
        }
    }

    public var entries: [Entry]
    /// `更新：` timestamp written by whoever changed the block last.
    public var updatedAt: Date?
    public var updatedAtText: String?
    /// The raw block, kept so a rewrite can preserve unknown keys.
    public var raw: String

    public init(entries: [Entry] = [], updatedAt: Date? = nil, updatedAtText: String? = nil, raw: String = "") {
        self.entries = entries
        self.updatedAt = updatedAt
        self.updatedAtText = updatedAtText
        self.raw = raw
    }

    public subscript(key: String) -> String? {
        entries.last { $0.key == key }?.value
    }

    public var isEmpty: Bool { entries.isEmpty }
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
    public enum Format: String, Hashable, Sendable { case markdown, json }

    public var format: Format
    /// Stable identity of this source file, shared by its Reminders records.
    public var sourceID: String?
    /// App release that last synchronized this file.
    public var hudexVersion: String?
    /// Human-readable contract for people and AI editors of this source.
    public var aiInstructions: [String]?
    public var schemaVersion: Int
    public var title: String?
    public var projects: [HudEXProject]
    public var diagnostics: [ParseDiagnostic]
    /// When the file was parsed.
    public var parsedAt: Date
    /// Modification date of the source file, used as an age fallback when a
    /// project has no parsable `更新：`.
    public var fileModifiedAt: Date?
    /// The optional settings block at the bottom of the file.
    public var settings: HudEXSettingsBlock?
    /// Text of the file with the settings block removed, so writing it back
    /// never has to touch the project content.
    public var bodyWithoutSettings: String

    public init(
        title: String? = nil,
        projects: [HudEXProject] = [],
        diagnostics: [ParseDiagnostic] = [],
        parsedAt: Date = Date(),
        fileModifiedAt: Date? = nil,
        settings: HudEXSettingsBlock? = nil,
        bodyWithoutSettings: String = "",
        format: Format = .markdown,
        sourceID: String? = nil,
        hudexVersion: String? = nil,
        aiInstructions: [String]? = nil,
        schemaVersion: Int = 1
    ) {
        self.format = format
        self.sourceID = sourceID
        self.hudexVersion = hudexVersion
        self.aiInstructions = aiInstructions
        self.schemaVersion = schemaVersion
        self.title = title
        self.projects = projects
        self.diagnostics = diagnostics
        self.parsedAt = parsedAt
        self.fileModifiedAt = fileModifiedAt
        self.settings = settings
        self.bodyWithoutSettings = bodyWithoutSettings
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
