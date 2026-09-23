import EventKit
import Foundation
import HudEXCore

@MainActor
final class RemindersSyncService {
    struct SyncResult {
        var document: HudEXDocument
        var removedLegacyLists: Int
        var retainedLegacyLists: Int
        var createdProjects: Int
        var projectCommandIdentifiers: [String]
        var projectCommandConflicts: Int
    }

    private struct TaskKey: Hashable {
        var projectID: String
        var taskID: String
    }

    private struct Marker {
        var sourceID: String
        var projectID: String
        var taskID: String
    }

    private struct ProjectCommand {
        var shortTitle: String
        var title: String
    }

    enum SyncError: LocalizedError {
        case accessDenied
        case noWritableListSource

        var errorDescription: String? {
            switch self {
            case .accessDenied: "Full access to Reminders was not granted."
            case .noWritableListSource: "No writable Reminders account is available."
            }
        }
    }

    static let managedListTitle = "HudEX · Synced"

    private let store = EKEventStore()
    private let markerScheme = "hudex-reminder"
    var onStoreChanged: (() -> Void)?

    init() {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.onStoreChanged?() }
        }
    }

    func sync(document input: HudEXDocument, appVersion: String) async throws -> SyncResult {
        guard input.format == .json else {
            throw NSError(domain: "HudEX.Reminders", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Convert the source file to JSON before syncing Reminders."])
        }
        guard try await store.requestFullAccessToReminders() else { throw SyncError.accessDenied }

        var document = input
        let sourceID = document.sourceID ?? UUID().uuidString.lowercased()
        document.sourceID = sourceID
        document.hudexVersion = appVersion
        document.aiInstructions = document.aiInstructions ?? HudEXJSONCodec.defaultAIInstructions
        document.schemaVersion = HudEXJSONCodec.currentVersion

        var tasksByProject: [String: [HudEXReminder]] = [:]
        for project in document.projects {
            tasksByProject[project.id, default: []] = project.reminders
        }

        let calendars = store.calendars(for: .reminder)
        let hadManagedList = calendars.contains(where: { $0.title == Self.managedListTitle })
        let calendar: EKCalendar
        if let existing = calendars.first(where: { $0.title == Self.managedListTitle && $0.allowsContentModifications }) {
            calendar = existing
        } else {
            guard let source = store.defaultCalendarForNewReminders()?.source
                    ?? calendars.first(where: { $0.allowsContentModifications })?.source else {
                throw SyncError.noWritableListSource
            }
            let created = EKCalendar(for: .reminder, eventStore: store)
            created.source = source
            created.title = Self.managedListTitle
            try store.saveCalendar(created, commit: true)
            calendar = created
        }

        var activeByKey: [TaskKey: EKReminder] = [:]
        for reminder in await fetchReminders(in: calendar) {
            guard let marker = marker(from: reminder.url) else { continue }
            let key = TaskKey(projectID: marker.projectID, taskID: marker.taskID)
            let belongsToDocument = marker.sourceID == sourceID
                && document.projects.contains(where: { $0.id == marker.projectID })
                && tasksByProject[marker.projectID, default: []].contains(where: { $0.id == marker.taskID })
            guard belongsToDocument else {
                try store.remove(reminder, commit: true)
                continue
            }
            if activeByKey[key] == nil {
                activeByKey[key] = reminder
            } else {
                // A partial earlier sync can leave a duplicate marker. Keep one
                // native reminder for each stable project/task ID pair.
                try store.remove(reminder, commit: true)
            }
        }

        var removedLegacyLists = 0
        var retainedLegacyLists = 0
        let legacyCalendars = calendars.filter { legacyProjectID(fromListTitle: $0.title) != nil }
        for legacyCalendar in legacyCalendars where legacyCalendar.calendarIdentifier != calendar.calendarIdentifier {
            guard legacyCalendar.allowsContentModifications else {
                retainedLegacyLists += 1
                continue
            }

            let projectID = legacyProjectID(fromListTitle: legacyCalendar.title)!
            let project = document.projects.first(where: { $0.id == projectID })
            for reminder in await fetchReminders(in: legacyCalendar) {
                guard let project else {
                    try store.remove(reminder, commit: true)
                    continue
                }

                if let taskID = legacyTaskID(from: reminder.url, projectID: projectID) {
                    let key = TaskKey(projectID: projectID, taskID: taskID)
                    guard tasksByProject[projectID, default: []].contains(where: { $0.id == taskID }) else {
                        try store.remove(reminder, commit: true)
                        continue
                    }
                    guard activeByKey[key] == nil else {
                        try store.remove(reminder, commit: true)
                        continue
                    }
                    reminder.calendar = calendar
                    reminder.url = taskURL(sourceID: sourceID, projectID: projectID, taskID: taskID)
                    reminder.title = displayTitle(
                        jsonTitle(from: reminder.title, project: project),
                        project: project
                    )
                    try store.save(reminder, commit: true)
                    activeByKey[key] = reminder
                } else {
                    // The previous implementation could leave a newly created
                    // item unmarked if HudEX closed before its next manual sync.
                    // These lists were created by HudEX for one project, so
                    // preserve such items while migrating them to the new list.
                    let taskID = UUID().uuidString.lowercased()
                    reminder.calendar = calendar
                    reminder.url = taskURL(sourceID: sourceID, projectID: projectID, taskID: taskID)
                    let title = jsonTitle(from: reminder.title, project: project)
                    reminder.title = displayTitle(title, project: project)
                    try store.save(reminder, commit: true)

                    var task = HudEXReminder(
                        id: taskID,
                        title: title,
                        notes: reminder.notes,
                        dueDate: dueDate(from: reminder),
                        isCompleted: reminder.isCompleted,
                        priority: reminder.priority,
                        reminderIdentifier: reminder.calendarItemIdentifier,
                        modifiedAt: reminder.lastModifiedDate ?? Date()
                    )
                    task.syncFingerprint = fingerprint(task)
                    tasksByProject[projectID, default: []].append(task)
                    activeByKey[TaskKey(projectID: projectID, taskID: taskID)] = reminder
                }
            }

            do {
                try store.removeCalendar(legacyCalendar, commit: true)
                removedLegacyLists += 1
            } catch {
                retainedLegacyLists += 1
            }
        }

        // EventKit invalidates fetched objects after store changes. Refetch the
        // managed list after migration and cleanup before applying the merge.
        let currentReminders = await fetchReminders(in: calendar)
        var byKey: [TaskKey: EKReminder] = [:]
        var nativeOnly: [EKReminder] = []
        var createdProjects = 0
        var projectCommandIdentifiers: [String] = []
        var projectCommandConflicts = 0
        for reminder in currentReminders {
            if let marker = marker(from: reminder.url), marker.sourceID == sourceID {
                let key = TaskKey(projectID: marker.projectID, taskID: marker.taskID)
                if byKey[key] == nil { byKey[key] = reminder }
            } else if marker(from: reminder.url) == nil {
                if isProjectCommandTitle(reminder.title) {
                    guard let command = projectCommand(from: reminder.title) else {
                        projectCommandConflicts += 1
                        continue
                    }
                    if let existing = document.projects.first(where: {
                        $0.shortTitle.localizedCaseInsensitiveCompare(command.shortTitle) == .orderedSame
                    }) {
                        if existing.title.localizedCaseInsensitiveCompare(command.title) == .orderedSame {
                            // A prior sync may have written the project but
                            // failed before consuming its command reminder.
                            projectCommandIdentifiers.append(reminder.calendarItemIdentifier)
                        } else {
                            projectCommandConflicts += 1
                        }
                        continue
                    }

                    var takenIDs = Set(document.projects.map(\.id))
                    let id = StableID.unique(
                        slug: StableID.slug(command.title),
                        taken: &takenIDs,
                        fallback: "project"
                    )
                    document.projects.append(HudEXProject(
                        id: id,
                        title: command.title,
                        shortTitle: command.shortTitle,
                        hasExplicitShortTitle: true,
                        status: .active,
                        statusText: "active",
                        updatedAt: nil,
                        updatedAtText: nil,
                        preamble: nil,
                        sections: []
                    ))
                    tasksByProject[id] = []
                    createdProjects += 1
                    projectCommandIdentifiers.append(reminder.calendarItemIdentifier)
                } else {
                    nativeOnly.append(reminder)
                }
            }
        }

        for reminder in nativeOnly {
            guard let project = project(forNativeTitle: reminder.title, in: document.projects) else { continue }
            let taskID = UUID().uuidString.lowercased()
            let title = jsonTitle(from: reminder.title, project: project)
            reminder.url = taskURL(sourceID: sourceID, projectID: project.id, taskID: taskID)
            reminder.title = displayTitle(title, project: project)
            try store.save(reminder, commit: true)

            var task = HudEXReminder(
                id: taskID,
                title: title,
                notes: reminder.notes,
                dueDate: dueDate(from: reminder),
                isCompleted: reminder.isCompleted,
                priority: reminder.priority,
                reminderIdentifier: reminder.calendarItemIdentifier,
                modifiedAt: reminder.lastModifiedDate ?? Date()
            )
            task.syncFingerprint = fingerprint(task)
            tasksByProject[project.id, default: []].append(task)
            byKey[TaskKey(projectID: project.id, taskID: taskID)] = reminder
        }

        var updatedProjects: [HudEXProject] = []
        for project in document.projects {
            var retained: [HudEXReminder] = []
            for var task in tasksByProject[project.id, default: []] {
                let key = TaskKey(projectID: project.id, taskID: task.id)
                if let native = byKey.removeValue(forKey: key) {
                    let nativeDate = native.lastModifiedDate ?? .distantPast
                    let nativeTask = HudEXReminder(
                        id: task.id,
                        title: jsonTitle(from: native.title, project: project),
                        notes: native.notes,
                        dueDate: dueDate(from: native),
                        isCompleted: native.isCompleted,
                        priority: native.priority
                    )
                    let fileChanged = task.syncFingerprint.map { $0 != fingerprint(task) } ?? true
                    let nativeChanged = task.syncFingerprint.map { $0 != fingerprint(nativeTask) } ?? false
                    let fileWins: Bool
                    if fileChanged && nativeChanged {
                        fileWins = (document.fileModifiedAt ?? .distantPast) >= nativeDate
                    } else {
                        fileWins = fileChanged
                    }

                    if nativeChanged && !fileWins {
                        task.title = nativeTask.title
                        task.notes = nativeTask.notes
                        task.dueDate = nativeTask.dueDate
                        task.isCompleted = nativeTask.isCompleted
                        task.priority = nativeTask.priority
                        task.modifiedAt = nativeDate
                    } else {
                        if fileWins { task.modifiedAt = Date() }
                    }

                    if apply(task, to: native, project: project, calendar: calendar, sourceID: sourceID) {
                        try store.save(native, commit: true)
                    }
                    task.reminderIdentifier = native.calendarItemIdentifier
                    task.syncFingerprint = fingerprint(task)
                    retained.append(task)
                } else if task.reminderIdentifier != nil && hadManagedList {
                    // A previously synchronized item missing from the managed
                    // list was deleted in Reminders.
                    continue
                } else {
                    let native = EKReminder(eventStore: store)
                    native.calendar = calendar
                    _ = apply(task, to: native, project: project, calendar: calendar, sourceID: sourceID)
                    try store.save(native, commit: true)
                    task.reminderIdentifier = native.calendarItemIdentifier
                    task.modifiedAt = native.lastModifiedDate ?? Date()
                    task.syncFingerprint = fingerprint(task)
                    retained.append(task)
                }
            }

            // Items still mapped here were removed from the source file.
            for removed in byKey.filter({ $0.key.projectID == project.id }).map(\.value) {
                try store.remove(removed, commit: true)
                byKey.removeValue(forKey: TaskKey(
                    projectID: project.id,
                    taskID: marker(from: removed.url)?.taskID ?? ""
                ))
            }

            updatedProjects.append(HudEXProject(
                id: project.id,
                title: project.title,
                shortTitle: project.shortTitle,
                hasExplicitShortTitle: project.hasExplicitShortTitle,
                status: project.status,
                statusText: project.statusText,
                updatedAt: project.updatedAt,
                updatedAtText: project.updatedAtText,
                preamble: project.preamble,
                sections: project.sections,
                sortOrder: project.sortOrder,
                colorOverride: project.colorOverride,
                priority: project.priority,
                reminders: retained
            ))
        }

        document.projects = updatedProjects
        return SyncResult(
            document: document,
            removedLegacyLists: removedLegacyLists,
            retainedLegacyLists: retainedLegacyLists,
            createdProjects: createdProjects,
            projectCommandIdentifiers: projectCommandIdentifiers,
            projectCommandConflicts: projectCommandConflicts
        )
    }

    func consumeProjectCommands(identifiers: [String]) async throws {
        guard !identifiers.isEmpty,
              let calendar = store.calendars(for: .reminder).first(where: {
                  $0.title == Self.managedListTitle && $0.allowsContentModifications
              }) else { return }
        let identifiers = Set(identifiers)
        for reminder in await fetchReminders(in: calendar)
        where identifiers.contains(reminder.calendarItemIdentifier) {
            try store.remove(reminder, commit: true)
        }
    }

    private func fetchReminders(in calendar: EKCalendar) async -> [EKReminder] {
        let predicate = store.predicateForReminders(in: [calendar])
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private func taskURL(sourceID: String, projectID: String, taskID: String) -> URL? {
        var components = URLComponents()
        components.scheme = markerScheme
        components.host = "task"
        components.queryItems = [
            URLQueryItem(name: "source", value: sourceID),
            URLQueryItem(name: "project", value: projectID),
            URLQueryItem(name: "id", value: taskID)
        ]
        return components.url
    }

    private func marker(from url: URL?) -> Marker? {
        guard let url, url.scheme == markerScheme, url.host == "task",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let sourceID = components.queryItems?.first(where: { $0.name == "source" })?.value,
              let projectID = components.queryItems?.first(where: { $0.name == "project" })?.value,
              let taskID = components.queryItems?.first(where: { $0.name == "id" })?.value else { return nil }
        return Marker(sourceID: sourceID, projectID: projectID, taskID: taskID)
    }

    private func legacyTaskID(from url: URL?, projectID: String) -> String? {
        guard let url, url.scheme == markerScheme, url.host == projectID else { return nil }
        return url.pathComponents.dropFirst().first
    }

    private func legacyProjectID(fromListTitle title: String) -> String? {
        let prefix = "HudEX · "
        guard title.hasPrefix(prefix), let opening = title.range(of: " [", options: .backwards)?.lowerBound,
              title.hasSuffix("]") else { return nil }
        let idStart = title.index(opening, offsetBy: 2)
        let idEnd = title.index(before: title.endIndex)
        let id = String(title[idStart..<idEnd])
        return id.isEmpty ? nil : id
    }

    private func project(forNativeTitle title: String, in projects: [HudEXProject]) -> HudEXProject? {
        if projects.count == 1 { return projects[0] }
        let matches = projects.filter { title.hasPrefix("\($0.shortTitle) · ") }
        return matches.count == 1 ? matches[0] : nil
    }

    private func projectCommand(from title: String) -> ProjectCommand? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let prefixRange = trimmed.range(of: "@project", options: [.anchored, .caseInsensitive]),
              prefixRange.upperBound < trimmed.endIndex,
              trimmed[prefixRange.upperBound].isWhitespace else {
            return nil
        }
        let payload = trimmed[prefixRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = payload.range(of: "|") else { return nil }
        let rawShortTitle = String(payload[..<separator.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawTitle = String(payload[separator.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard rawShortTitle.count <= ShortTitle.maxLength,
              let shortTitle = ShortTitle.sanitizeExplicit(rawShortTitle),
              !rawTitle.isEmpty else { return nil }
        return ProjectCommand(shortTitle: shortTitle, title: rawTitle)
    }

    private func isProjectCommandTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let prefix = trimmed.range(of: "@project", options: [.anchored, .caseInsensitive]) else { return false }
        return prefix.upperBound == trimmed.endIndex || trimmed[prefix.upperBound].isWhitespace
    }

    private func displayTitle(_ title: String, project: HudEXProject) -> String {
        "\(project.shortTitle) · \(title)"
    }

    private func jsonTitle(from title: String, project: HudEXProject) -> String {
        let prefix = "\(project.shortTitle) · "
        return title.hasPrefix(prefix) ? String(title.dropFirst(prefix.count)) : title
    }

    /// Applies HudEX content and the stable source/project/task marker. Returns
    /// whether the EventKit object actually changed so notification feedback
    /// cannot cause an endless sync loop.
    private func apply(
        _ task: HudEXReminder,
        to reminder: EKReminder,
        project: HudEXProject,
        calendar: EKCalendar,
        sourceID: String
    ) -> Bool {
        var changed = false
        let visibleTitle = displayTitle(task.title, project: project)
        if reminder.title != visibleTitle { reminder.title = visibleTitle; changed = true }
        if reminder.notes != task.notes { reminder.notes = task.notes; changed = true }
        if reminder.calendar?.calendarIdentifier != calendar.calendarIdentifier { reminder.calendar = calendar; changed = true }
        let url = taskURL(sourceID: sourceID, projectID: project.id, taskID: task.id)
        if reminder.url != url { reminder.url = url; changed = true }
        let priority = min(max(task.priority, 0), 9)
        if reminder.priority != priority { reminder.priority = priority; changed = true }
        if !sameMinute(dueDate(from: reminder), task.dueDate) {
            reminder.dueDateComponents = task.dueDate.map(dueDateComponents(from:))
            changed = true
        }
        if reminder.isCompleted != task.isCompleted { reminder.isCompleted = task.isCompleted; changed = true }
        return changed
    }

    private func dueDateComponents(from date: Date) -> DateComponents {
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .current
        return components
    }

    private func dueDate(from reminder: EKReminder) -> Date? {
        guard let components = reminder.dueDateComponents else { return nil }
        return Calendar.current.date(from: components)
    }

    private func sameMinute(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (left?, right?): Int(left.timeIntervalSince1970 / 60) == Int(right.timeIntervalSince1970 / 60)
        default: false
        }
    }

    private func fingerprint(_ task: HudEXReminder) -> String {
        let values = [
            task.title,
            task.notes ?? "",
            task.dueDate.map { String(Int($0.timeIntervalSince1970 / 60)) } ?? "",
            task.isCompleted ? "1" : "0",
            String(task.priority)
        ].joined(separator: "\u{1f}")
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in values.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
