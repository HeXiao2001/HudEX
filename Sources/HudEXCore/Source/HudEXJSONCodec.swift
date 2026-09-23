import Foundation

/// Versioned, human-readable source format for projects and reminders.
public enum HudEXJSONCodec {
    public static let currentVersion = 1

    public struct File: Codable, Sendable {
        public var schemaVersion: Int
        public var title: String?
        public var projects: [Project]
        public var settings: [String: String]?

        public init(schemaVersion: Int = currentVersion, title: String? = nil, projects: [Project], settings: [String: String]? = nil) {
            self.schemaVersion = schemaVersion
            self.title = title
            self.projects = projects
            self.settings = settings
        }
    }

    public struct Project: Codable, Sendable {
        public var id: String
        public var title: String
        public var shortTitle: String?
        public var status: String?
        public var updatedAt: Date?
        public var preamble: String?
        public var sections: [Section]
        public var sortOrder: Int?
        public var color: String?
        public var priority: String?
        public var reminders: [Reminder]

        public init(
            id: String, title: String, shortTitle: String? = nil, status: String? = nil,
            updatedAt: Date? = nil, preamble: String? = nil, sections: [Section] = [],
            sortOrder: Int? = nil, color: String? = nil, priority: String? = nil,
            reminders: [Reminder] = []
        ) {
            self.id = id; self.title = title; self.shortTitle = shortTitle; self.status = status
            self.updatedAt = updatedAt; self.preamble = preamble; self.sections = sections
            self.sortOrder = sortOrder; self.color = color; self.priority = priority
            self.reminders = reminders
        }
    }

    public struct Section: Codable, Sendable {
        public var id: String
        public var title: String
        public var body: String
        public init(id: String, title: String, body: String) {
            self.id = id; self.title = title; self.body = body
        }
    }

    public struct Reminder: Codable, Sendable {
        public var id: String
        public var title: String
        public var notes: String?
        public var dueDate: Date?
        public var isCompleted: Bool
        public var priority: Int
        public var reminderIdentifier: String?
        public var modifiedAt: Date?
        public var syncFingerprint: String?

        public init(
            id: String, title: String, notes: String? = nil, dueDate: Date? = nil,
            isCompleted: Bool = false, priority: Int = 0,
            reminderIdentifier: String? = nil, modifiedAt: Date? = nil,
            syncFingerprint: String? = nil
        ) {
            self.id = id; self.title = title; self.notes = notes; self.dueDate = dueDate
            self.isCompleted = isCompleted; self.priority = priority
            self.reminderIdentifier = reminderIdentifier; self.modifiedAt = modifiedAt
            self.syncFingerprint = syncFingerprint
        }
    }

    public enum CodecError: Error, LocalizedError {
        case unsupportedVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version): "Unsupported HudEX JSON schema version: \(version)"
            }
        }
    }

    public static func decode(_ data: Data, fileModifiedAt: Date? = nil, now: Date = Date()) throws -> HudEXDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(File.self, from: data)
        guard file.schemaVersion == currentVersion else { throw CodecError.unsupportedVersion(file.schemaVersion) }
        let projects = file.projects.map { item in
            HudEXProject(
                id: item.id,
                title: item.title,
                shortTitle: ShortTitle.sanitizeExplicit(item.shortTitle ?? "")
                    ?? ShortTitle.derive(from: item.title),
                hasExplicitShortTitle: item.shortTitle != nil,
                status: ProjectStatus.parse(item.status ?? ""),
                statusText: item.status,
                updatedAt: item.updatedAt,
                updatedAtText: item.updatedAt.map(TimestampFormatter.string(from:)),
                preamble: item.preamble,
                sections: item.sections.map { ProjectSection(id: $0.id, title: $0.title, body: $0.body) },
                sortOrder: item.sortOrder,
                colorOverride: item.color,
                priority: ProjectPriority.parse(item.priority),
                reminders: item.reminders.map {
                    HudEXReminder(id: $0.id, title: $0.title, notes: $0.notes, dueDate: $0.dueDate,
                                  isCompleted: $0.isCompleted, priority: $0.priority,
                                  reminderIdentifier: $0.reminderIdentifier, modifiedAt: $0.modifiedAt,
                                  syncFingerprint: $0.syncFingerprint)
                }
            )
        }
        let settings = file.settings.map { values in
            HudEXSettingsBlock(
                entries: values.keys.sorted().map { HudEXSettingsBlock.Entry(key: $0, value: values[$0] ?? "") },
                raw: "json"
            )
        }
        return HudEXDocument(title: file.title, projects: projects, parsedAt: now,
                             fileModifiedAt: fileModifiedAt, settings: settings, format: .json)
    }

    public static func encode(_ document: HudEXDocument) throws -> Data {
        let file = File(
            title: document.title,
            projects: document.projects.map { item in
                Project(
                    id: item.id, title: item.title,
                    shortTitle: item.hasExplicitShortTitle ? item.shortTitle : nil,
                    status: item.statusText,
                    updatedAt: item.updatedAt,
                    preamble: item.preamble,
                    sections: item.sections.map { Section(id: $0.id, title: $0.title, body: $0.body) },
                    sortOrder: item.sortOrder, color: item.colorOverride, priority: item.priority?.rawValue,
                    reminders: item.reminders.map {
                        Reminder(id: $0.id, title: $0.title, notes: $0.notes, dueDate: $0.dueDate,
                                 isCompleted: $0.isCompleted, priority: $0.priority,
                                 reminderIdentifier: $0.reminderIdentifier, modifiedAt: $0.modifiedAt,
                                 syncFingerprint: $0.syncFingerprint)
                    }
                )
            },
            settings: document.settings.map { block in
                Dictionary(block.entries.map { ($0.key, $0.value) }, uniquingKeysWith: { _, newer in newer })
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }
}
