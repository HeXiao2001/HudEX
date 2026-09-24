import Foundation

/// Versioned, human-readable source format for projects and reminders.
public enum HudEXJSONCodec {
    public static let currentVersion = 6

    /// Kept in the source file so future people and AI editors follow the same
    /// ownership and Reminders rules as the app.
    public static let defaultAIInstructions = [
        "This single HudEX.json file contains all project context, settings, and reminders. Keep one projects array and one top-level reminders array. Do not create a second HudEX data file.",
        "All reminders sync through one Apple Reminders list named HudEX. Projects are visible HudEX tags inside this JSON file, not separate Reminders lists. Every project must have a stable unique id and a distinct shortTitle. Set each project reminder's projectID to that id; standalone reminders omit projectID. A reminder created directly in the HudEX list is standalone unless its title starts with a unique project shortTitle followed by ' · '.",
        "When updating a project, derive specific actionable reminders from its next-step or commitment text. Create a reminder only for an actual action; do not turn general notes into tasks. A project may have many reminders. Keep existing actionable reminders and their stable ids when revising text, and avoid duplicates.",
        "For a new reminder use a new UUID id and a concise verb-led title. Put optional context in notes. Preserve sourceID, project ids, reminder ids, and sync metadata. Do not invent reminderIdentifier, modifiedAt, or syncFingerprint; HudEX writes them during sync.",
        "Use ISO 8601 dueDate and startDate only when explicit dates and times are known. Do not guess a time. A timed dueDate produces an alert; earlyReminderMinutes adds an earlier alert. Priority is 0 for none, 1 for high, 5 for medium, and 9 for low.",
        "Use location for a readable place name. Add locationAlert only when exact latitude and longitude are known: title, latitude, longitude, radiusMeters, and trigger (arrive or leave). A repeatRule may use daily, weekly, monthly, or yearly frequency and a positive interval; frequency none clears repetition. Keep isFlagged and tags as HudEX metadata; Apple's public EventKit API does not expose their native Reminders equivalents.",
        "Keep project sections and settings. Edit or delete a reminder by its stable id. HudEX syncs the single HudEX list and all reminders in both directions and updates hudexVersion."
    ]

    public struct File: Codable, Sendable {
        public var schemaVersion: Int
        public var sourceID: String?
        public var hudexVersion: String?
        public var aiInstructions: [String]?
        public var title: String?
        public var projects: [Project]
        public var reminders: [Reminder]
        public var settings: [String: String]?

        private enum CodingKeys: String, CodingKey {
            case schemaVersion, sourceID, hudexVersion, aiInstructions, title, projects, reminders, settings
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            sourceID = try container.decodeIfPresent(String.self, forKey: .sourceID)
            hudexVersion = try container.decodeIfPresent(String.self, forKey: .hudexVersion)
            aiInstructions = try container.decodeIfPresent([String].self, forKey: .aiInstructions)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            projects = try container.decodeIfPresent([Project].self, forKey: .projects) ?? []
            reminders = try container.decodeIfPresent([Reminder].self, forKey: .reminders) ?? []
            settings = try container.decodeIfPresent([String: String].self, forKey: .settings)
        }

        public init(
            schemaVersion: Int = currentVersion,
            sourceID: String? = nil,
            hudexVersion: String? = nil,
            aiInstructions: [String]? = nil,
            title: String? = nil,
            projects: [Project],
            reminders: [Reminder] = [],
            settings: [String: String]? = nil
        ) {
            self.schemaVersion = schemaVersion
            self.sourceID = sourceID
            self.hudexVersion = hudexVersion
            self.aiInstructions = aiInstructions
            self.title = title
            self.projects = projects
            self.reminders = reminders
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

        private enum CodingKeys: String, CodingKey {
            case id, title, shortTitle, status, updatedAt, preamble, sections, sortOrder, color, priority, reminders
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            shortTitle = try container.decodeIfPresent(String.self, forKey: .shortTitle)
            status = try container.decodeIfPresent(String.self, forKey: .status)
            updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
            preamble = try container.decodeIfPresent(String.self, forKey: .preamble)
            sections = try container.decodeIfPresent([Section].self, forKey: .sections) ?? []
            sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder)
            color = try container.decodeIfPresent(String.self, forKey: .color)
            priority = try container.decodeIfPresent(String.self, forKey: .priority)
            reminders = try container.decodeIfPresent([Reminder].self, forKey: .reminders) ?? []
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(title, forKey: .title)
            try container.encodeIfPresent(shortTitle, forKey: .shortTitle)
            try container.encodeIfPresent(status, forKey: .status)
            try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
            try container.encodeIfPresent(preamble, forKey: .preamble)
            try container.encode(sections, forKey: .sections)
            try container.encodeIfPresent(sortOrder, forKey: .sortOrder)
            try container.encodeIfPresent(color, forKey: .color)
            try container.encodeIfPresent(priority, forKey: .priority)
        }

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
        public var startDate: Date?
        public var location: String?
        public var locationAlert: HudEXReminderLocationAlert?
        public var repeatRule: HudEXReminderRepeatRule?
        public var earlyReminderMinutes: Int?
        public var isCompleted: Bool
        public var priority: Int
        public var isFlagged: Bool
        public var tags: [String]
        public var reminderIdentifier: String?
        public var projectID: String?
        public var modifiedAt: Date?
        public var syncFingerprint: String?

        private enum CodingKeys: String, CodingKey {
            case id, title, notes, dueDate, startDate, location, locationAlert, repeatRule,
                 earlyReminderMinutes, isCompleted, priority, isFlagged, tags, reminderIdentifier,
                 projectID, modifiedAt, syncFingerprint
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            notes = try container.decodeIfPresent(String.self, forKey: .notes)
            dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
            startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
            location = try container.decodeIfPresent(String.self, forKey: .location)
            locationAlert = try container.decodeIfPresent(HudEXReminderLocationAlert.self, forKey: .locationAlert)
            repeatRule = try container.decodeIfPresent(HudEXReminderRepeatRule.self, forKey: .repeatRule)
            earlyReminderMinutes = try container.decodeIfPresent(Int.self, forKey: .earlyReminderMinutes)
            isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
            priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 0
            isFlagged = try container.decodeIfPresent(Bool.self, forKey: .isFlagged) ?? false
            tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
            reminderIdentifier = try container.decodeIfPresent(String.self, forKey: .reminderIdentifier)
            projectID = try container.decodeIfPresent(String.self, forKey: .projectID)
            modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt)
            syncFingerprint = try container.decodeIfPresent(String.self, forKey: .syncFingerprint)
        }

        public init(
            id: String, title: String, notes: String? = nil, dueDate: Date? = nil,
            startDate: Date? = nil, location: String? = nil,
            locationAlert: HudEXReminderLocationAlert? = nil,
            repeatRule: HudEXReminderRepeatRule? = nil, earlyReminderMinutes: Int? = nil,
            isCompleted: Bool = false, priority: Int = 0, isFlagged: Bool = false,
            tags: [String] = [],
            reminderIdentifier: String? = nil, modifiedAt: Date? = nil,
            syncFingerprint: String? = nil, projectID: String? = nil
        ) {
            self.id = id; self.title = title; self.notes = notes; self.dueDate = dueDate
            self.startDate = startDate; self.location = location; self.locationAlert = locationAlert
            self.repeatRule = repeatRule; self.earlyReminderMinutes = earlyReminderMinutes
            self.isCompleted = isCompleted; self.priority = priority
            self.isFlagged = isFlagged; self.tags = tags
            self.reminderIdentifier = reminderIdentifier; self.modifiedAt = modifiedAt
            self.syncFingerprint = syncFingerprint
            self.projectID = projectID
        }
    }

    public enum CodecError: Error, LocalizedError {
        case unsupportedVersion(Int)
        case invalidReminder(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version): "Unsupported HudEX JSON schema version: \(version)"
            case .invalidReminder(let reason): "Invalid HudEX reminder: \(reason)"
            }
        }
    }

    public static func decode(_ data: Data, fileModifiedAt: Date? = nil, now: Date = Date()) throws -> HudEXDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(File.self, from: data)
        guard (1...currentVersion).contains(file.schemaVersion) else {
            throw CodecError.unsupportedVersion(file.schemaVersion)
        }
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
                reminders: []
            )
        }
        // Version 1/2 stored tasks under projects. Flatten on read so the next
        // successful sync writes the version 3 format without losing identities.
        let legacy = file.projects.flatMap { project in
            project.reminders.map { ($0, project.id) }
        }
        let reminders = (file.reminders.map { ($0, $0.projectID) } + legacy).map { item, projectID in
            HudEXReminder(id: item.id, projectID: projectID, title: item.title,
                          notes: item.notes, dueDate: item.dueDate, startDate: item.startDate,
                          location: item.location, locationAlert: item.locationAlert,
                          repeatRule: item.repeatRule, earlyReminderMinutes: item.earlyReminderMinutes,
                          isCompleted: item.isCompleted, priority: item.priority,
                          isFlagged: item.isFlagged, tags: item.tags,
                          reminderIdentifier: item.reminderIdentifier, modifiedAt: item.modifiedAt,
                          syncFingerprint: item.syncFingerprint)
        }
        var seenReminderIDs = Set<String>()
        for reminder in reminders {
            guard !reminder.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !reminder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seenReminderIDs.insert(reminder.id).inserted else {
                throw CodecError.invalidReminder("ids must be unique and ids/titles cannot be empty")
            }
            if let early = reminder.earlyReminderMinutes, !(0...525600).contains(early) {
                throw CodecError.invalidReminder("earlyReminderMinutes must be between 0 and 525600")
            }
            if let rule = reminder.repeatRule, !(1...365).contains(rule.interval) {
                throw CodecError.invalidReminder("repeatRule.interval must be between 1 and 365")
            }
            if let place = reminder.locationAlert,
               !(-90...90).contains(place.latitude) || !(-180...180).contains(place.longitude)
                || !(1...100000).contains(place.radiusMeters) {
                throw CodecError.invalidReminder("locationAlert coordinates or radius are invalid")
            }
        }
        let settings = file.settings.map { values in
            HudEXSettingsBlock(
                entries: values.keys.sorted().map { HudEXSettingsBlock.Entry(key: $0, value: values[$0] ?? "") },
                raw: "json"
            )
        }
        return HudEXDocument(
            title: file.title,
            projects: projects,
            reminders: reminders,
            parsedAt: now,
            fileModifiedAt: fileModifiedAt,
            settings: settings,
            format: .json,
            sourceID: file.sourceID,
            hudexVersion: file.hudexVersion,
            aiInstructions: file.aiInstructions,
            schemaVersion: file.schemaVersion
        )
    }

    public static func encode(_ document: HudEXDocument) throws -> Data {
        let file = File(
            schemaVersion: currentVersion,
            sourceID: document.sourceID,
            hudexVersion: document.hudexVersion,
            aiInstructions: document.aiInstructions,
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
                    reminders: []
                )
            },
            reminders: document.reminders.map {
                Reminder(id: $0.id, title: $0.title, notes: $0.notes, dueDate: $0.dueDate,
                         startDate: $0.startDate, location: $0.location,
                         locationAlert: $0.locationAlert, repeatRule: $0.repeatRule,
                         earlyReminderMinutes: $0.earlyReminderMinutes,
                         isCompleted: $0.isCompleted, priority: $0.priority,
                         isFlagged: $0.isFlagged, tags: $0.tags,
                         reminderIdentifier: $0.reminderIdentifier, modifiedAt: $0.modifiedAt,
                         syncFingerprint: $0.syncFingerprint, projectID: $0.projectID)
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
