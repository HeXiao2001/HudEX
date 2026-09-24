import CoreLocation
import EventKit
import Foundation
import HudEXCore

@MainActor
final class RemindersSyncService {
    struct SyncResult {
        var document: HudEXDocument
        var createdProjects: Int
        var projectCommandIdentifiers: [String]
        var projectCommandConflicts: Int
    }

    struct LegacyCleanupResult {
        var removed: Int
        var retained: Int
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

    static let managedListTitle = "HudEX"
    private static let standaloneProjectID = "__hudex_standalone__"
    private static let oldSharedListTitle = "HudEX · Synced"
    private static let inboxListTitle = "HudEX · Inbox"

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
        if document.schemaVersion < HudEXJSONCodec.currentVersion || document.aiInstructions == nil
            || document.aiInstructions?.contains(where: { $0.contains("HudEX · Synced") }) == true {
            document.aiInstructions = HudEXJSONCodec.defaultAIInstructions
        }
        document.schemaVersion = HudEXJSONCodec.currentVersion

        // Project buckets live only in JSON. Every task uses the same native
        // Reminders list, with its project ID kept in the stable URL marker.
        let realProjectIDs = Set(document.projects.map(\.id))
        document.projects = document.projects.map { project in
            var copy = project
            copy.reminders = document.reminders.filter { $0.projectID == project.id }
            return copy
        }
        let standalone = HudEXProject(
            id: Self.standaloneProjectID, title: "Reminders", shortTitle: "",
            hasExplicitShortTitle: false, status: .active, statusText: nil,
            updatedAt: nil, updatedAtText: nil, preamble: nil, sections: [],
            reminders: document.reminders.filter {
                $0.projectID == nil || !realProjectIDs.contains($0.projectID!)
            }
        )
        document.projects.append(standalone)

        var tasksByProject: [String: [HudEXReminder]] = [:]
        for project in document.projects {
            tasksByProject[project.id, default: []] = project.reminders
        }

        let existingCalendars = store.calendars(for: .reminder)
        let hadManagedList = existingCalendars.contains(where: { isManagedListTitle($0.title) })
        let calendar = try writableCalendar(existing: existingCalendars)
        let oldCalendars = existingCalendars.filter {
            $0.calendarIdentifier != calendar.calendarIdentifier && isManagedListTitle($0.title)
        }
        var currentReminders: [EKReminder] = []
        for list in [calendar] + oldCalendars {
            currentReminders += await fetchReminders(in: list)
        }

        var byKey: [String: EKReminder] = [:]
        var nativeOnly: [(reminder: EKReminder, project: HudEXProject)] = []
        var createdProjects = 0
        var projectCommandIdentifiers: [String] = []
        var projectCommandConflicts = 0
        for reminder in currentReminders {
            if let marker = marker(from: reminder.url), marker.sourceID == sourceID {
                if byKey[marker.taskID] == nil { byKey[marker.taskID] = reminder }
            } else if marker(from: reminder.url) == nil {
                let oldProjectID = legacyProjectID(fromListTitle: reminder.calendar?.title ?? "")
                if let oldProjectID, let taskID = legacyTaskID(from: reminder.url, projectID: oldProjectID),
                   tasksByProject.values.contains(where: { $0.contains(where: { $0.id == taskID }) }) {
                    reminder.url = taskURL(sourceID: sourceID, projectID: oldProjectID, taskID: taskID)
                    try store.save(reminder, commit: true)
                    byKey[taskID] = reminder
                    continue
                }
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
                    let assigned = document.projects.first(where: {
                        $0.id != Self.standaloneProjectID && $0.id == oldProjectID
                    }) ?? project(forNativeTitle: reminder.title, in: document.projects)
                    if let assigned { nativeOnly.append((reminder, assigned)) }
                }
            }
        }

        for (reminder, project) in nativeOnly {
            let taskID = UUID().uuidString.lowercased()
            let title = jsonTitle(from: reminder.title, project: project)
            reminder.calendar = calendar
            reminder.url = taskURL(sourceID: sourceID, projectID: project.id, taskID: taskID)
            reminder.title = displayTitle(title, project: project)
            try store.save(reminder, commit: true)

            var task = HudEXReminder(
                id: taskID,
                title: title,
                notes: reminder.notes,
                dueDate: dueDate(from: reminder),
                startDate: startDate(from: reminder),
                location: reminder.location,
                locationAlert: locationAlert(from: reminder),
                repeatRule: repeatRule(from: reminder),
                earlyReminderMinutes: earlyReminderMinutes(from: reminder),
                isCompleted: reminder.isCompleted,
                priority: reminder.priority,
                reminderIdentifier: reminder.calendarItemIdentifier,
                modifiedAt: reminder.lastModifiedDate ?? Date()
            )
            task.syncFingerprint = fingerprint(task)
            tasksByProject[project.id, default: []].append(task)
        }

        // EventKit can invalidate fetched objects after a save or list move.
        byKey.removeAll()
        for list in [calendar] + oldCalendars {
            for reminder in await fetchReminders(in: list) {
                guard let marker = marker(from: reminder.url), marker.sourceID == sourceID else { continue }
                byKey[marker.taskID] = reminder
            }
        }

        var updatedProjects: [HudEXProject] = []
        for project in document.projects {
            var retained: [HudEXReminder] = []
            for var task in tasksByProject[project.id, default: []] {
                if let native = byKey.removeValue(forKey: task.id) {
                    let nativeDate = native.lastModifiedDate ?? .distantPast
                    let nativeTask = HudEXReminder(
                        id: task.id,
                        title: jsonTitle(from: native.title, project: project),
                        notes: native.notes,
                        dueDate: dueDate(from: native),
                        startDate: startDate(from: native),
                        location: native.location,
                        locationAlert: locationAlert(from: native),
                        repeatRule: repeatRule(from: native),
                        earlyReminderMinutes: earlyReminderMinutes(from: native),
                        isCompleted: native.isCompleted,
                        priority: native.priority
                    )
                    let isCurrentFingerprint = task.syncFingerprint?.hasPrefix("v2:") == true
                    let fileChanged = task.syncFingerprint.map {
                        $0 != (isCurrentFingerprint ? fingerprint(task) : legacyFingerprint(task))
                    } ?? true
                    let nativeChanged = task.syncFingerprint.map {
                        $0 != (isCurrentFingerprint ? fingerprint(nativeTask) : legacyFingerprint(nativeTask))
                    } ?? false
                    if !isCurrentFingerprint {
                        // Earlier JSON versions had no fields for these native
                        // details. Import them before writing anything back.
                        task.startDate = task.startDate ?? nativeTask.startDate
                        task.location = task.location ?? nativeTask.location
                        task.locationAlert = task.locationAlert ?? nativeTask.locationAlert
                        task.repeatRule = task.repeatRule ?? nativeTask.repeatRule
                        task.earlyReminderMinutes = task.earlyReminderMinutes ?? nativeTask.earlyReminderMinutes
                    }
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
                        task.startDate = nativeTask.startDate
                        task.location = nativeTask.location
                        task.locationAlert = nativeTask.locationAlert
                        task.repeatRule = nativeTask.repeatRule
                        task.earlyReminderMinutes = nativeTask.earlyReminderMinutes
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
            for removed in byKey.filter({ marker(from: $0.value.url)?.projectID == project.id }).map(\.value) {
                try store.remove(removed, commit: true)
                byKey.removeValue(forKey: marker(from: removed.url)?.taskID ?? "")
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

        // A deleted project leaves its native reminders in the old list. They
        // are removed only if absent from JSON, using their stable task ID.
        for removed in byKey.values {
            try store.remove(removed, commit: true)
        }
        document.reminders = updatedProjects.flatMap { project in
            project.reminders.map { task in
                var copy = task
                copy.projectID = project.id == Self.standaloneProjectID ? nil : project.id
                return copy
            }
        }
        document.projects = updatedProjects.filter { $0.id != Self.standaloneProjectID }.map { project in
            var copy = project
            copy.reminders = []
            return copy
        }
        return SyncResult(
            document: document,
            createdProjects: createdProjects,
            projectCommandIdentifiers: projectCommandIdentifiers,
            projectCommandConflicts: projectCommandConflicts
        )
    }

    func consumeProjectCommands(identifiers: [String]) async throws {
        guard !identifiers.isEmpty else { return }
        let identifiers = Set(identifiers)
        for calendar in store.calendars(for: .reminder)
        where isManagedListTitle(calendar.title) && calendar.allowsContentModifications {
            for reminder in await fetchReminders(in: calendar)
            where identifiers.contains(reminder.calendarItemIdentifier) {
                try store.remove(reminder, commit: true)
            }
        }
    }

    /// Run only after the reconciled JSON has been saved. Never remove a list
    /// that still contains a reminder (including one from another source).
    func cleanupLegacyLists() async -> LegacyCleanupResult {
        var result = LegacyCleanupResult(removed: 0, retained: 0)
        for calendar in store.calendars(for: .reminder)
        where calendar.title != Self.managedListTitle && isManagedListTitle(calendar.title) {
            guard calendar.allowsContentModifications,
                  await fetchReminders(in: calendar).isEmpty else {
                result.retained += 1
                continue
            }
            do {
                try store.removeCalendar(calendar, commit: true)
                result.removed += 1
            } catch {
                result.retained += 1
            }
        }
        return result
    }

    private func fetchReminders(in calendar: EKCalendar) async -> [EKReminder] {
        let predicate = store.predicateForReminders(in: [calendar])
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private func writableCalendar(existing: [EKCalendar]) throws -> EKCalendar {
        if let calendar = existing.first(where: {
            $0.title == Self.managedListTitle && $0.allowsContentModifications
        }) { return calendar }
        // Reuse the Inbox identifier first: existing desktop widgets pointing
        // to it keep working after this list is renamed to plain “HudEX”.
        if let previous = existing.first(where: {
            ($0.title == Self.inboxListTitle || $0.title == Self.oldSharedListTitle)
                && $0.allowsContentModifications
        }) {
            previous.title = Self.managedListTitle
            try store.saveCalendar(previous, commit: true)
            return previous
        }
        guard let source = store.defaultCalendarForNewReminders()?.source
                ?? existing.first(where: { $0.allowsContentModifications })?.source else {
            throw SyncError.noWritableListSource
        }
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.source = source
        calendar.title = Self.managedListTitle
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }

    private func isManagedListTitle(_ title: String) -> Bool {
        title == Self.managedListTitle || title == Self.inboxListTitle
            || title == Self.oldSharedListTitle || legacyProjectID(fromListTitle: title) != nil
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
        let matches = projects.filter {
            $0.id != Self.standaloneProjectID && title.hasPrefix("\($0.shortTitle) · ")
        }
        if matches.count == 1 { return matches[0] }
        return projects.first(where: { $0.id == Self.standaloneProjectID })
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
        return title
    }

    private func jsonTitle(from title: String, project: HudEXProject) -> String {
        if project.id == Self.standaloneProjectID { return title }
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
        if reminder.location != task.location { reminder.location = task.location; changed = true }
        let priority = min(max(task.priority, 0), 9)
        if reminder.priority != priority { reminder.priority = priority; changed = true }
        let oldDue = dueDate(from: reminder)
        let oldEarlyMinutes = earlyReminderMinutes(from: reminder)
        let oldLocationAlert = locationAlert(from: reminder)
        if !sameMinute(oldDue, task.dueDate) {
            reminder.dueDateComponents = task.dueDate.map(dueDateComponents(from:))
            changed = true
        }
        if !sameMinute(startDate(from: reminder), task.startDate) {
            reminder.startDateComponents = task.startDate.map(dueDateComponents(from:))
            changed = true
        }
        if repeatRule(from: reminder) != task.repeatRule,
           task.repeatRule != nil || repeatRule(from: reminder) != nil {
            for rule in reminder.recurrenceRules ?? [] { reminder.removeRecurrenceRule(rule) }
            if let rule = task.repeatRule, rule.frequency != .none {
                let frequency: EKRecurrenceFrequency
                switch rule.frequency {
                case .none: frequency = .daily
                case .daily: frequency = .daily
                case .weekly: frequency = .weekly
                case .monthly: frequency = .monthly
                case .yearly: frequency = .yearly
                }
                reminder.addRecurrenceRule(EKRecurrenceRule(
                    recurrenceWith: frequency, interval: rule.interval, end: nil
                ))
            }
            changed = true
        }
        var desiredAlarms = (reminder.alarms ?? []).filter { alarm in
            if alarm.structuredLocation != nil { return oldLocationAlert == nil }
            if sameMinute(alarm.absoluteDate, oldDue), oldDue != nil { return false }
            if let oldDue, let oldEarlyMinutes, oldEarlyMinutes > 0,
               sameMinute(alarm.absoluteDate, oldDue.addingTimeInterval(-Double(oldEarlyMinutes * 60))) {
                return false
            }
            return true
        }
        if let due = task.dueDate {
            desiredAlarms.append(EKAlarm(absoluteDate: due))
            if let early = task.earlyReminderMinutes, early > 0 {
                desiredAlarms.append(EKAlarm(absoluteDate: due.addingTimeInterval(-Double(early * 60))))
            }
        }
        if let alert = task.locationAlert {
            let location = EKStructuredLocation(title: alert.title)
            location.geoLocation = CLLocation(latitude: alert.latitude, longitude: alert.longitude)
            location.radius = alert.radiusMeters
            let alarm = EKAlarm(relativeOffset: 0)
            alarm.structuredLocation = location
            alarm.proximity = alert.trigger == .arrive ? .enter : .leave
            desiredAlarms.append(alarm)
        }
        if alarmSignatures(reminder.alarms ?? []) != alarmSignatures(desiredAlarms) {
            reminder.alarms = desiredAlarms.isEmpty ? nil : desiredAlarms
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

    private func startDate(from reminder: EKReminder) -> Date? {
        guard let components = reminder.startDateComponents else { return nil }
        return Calendar.current.date(from: components)
    }

    private func earlyReminderMinutes(from reminder: EKReminder) -> Int? {
        guard let due = dueDate(from: reminder) else { return nil }
        let minutes = (reminder.alarms ?? []).compactMap { alarm -> Int? in
            if let absolute = alarm.absoluteDate {
                let value = Int((due.timeIntervalSince(absolute) / 60).rounded())
                return value > 0 ? value : nil
            }
            if alarm.structuredLocation == nil && alarm.relativeOffset < 0 {
                return Int((-alarm.relativeOffset / 60).rounded())
            }
            return nil
        }
        return minutes.min()
    }

    private func locationAlert(from reminder: EKReminder) -> HudEXReminderLocationAlert? {
        guard let alarm = reminder.alarms?.first(where: { $0.structuredLocation?.geoLocation != nil }),
              let place = alarm.structuredLocation, let coordinate = place.geoLocation?.coordinate else { return nil }
        return HudEXReminderLocationAlert(
            title: place.title ?? reminder.location ?? "Location",
            latitude: coordinate.latitude, longitude: coordinate.longitude,
            radiusMeters: place.radius,
            trigger: alarm.proximity == .leave ? .leave : .arrive
        )
    }

    private func repeatRule(from reminder: EKReminder) -> HudEXReminderRepeatRule? {
        guard let rules = reminder.recurrenceRules, rules.count == 1,
              let rule = rules.first, rule.recurrenceEnd == nil,
              rule.daysOfTheWeek == nil, rule.daysOfTheMonth == nil,
              rule.monthsOfTheYear == nil, rule.weeksOfTheYear == nil,
              rule.daysOfTheYear == nil, rule.setPositions == nil else { return nil }
        let frequency: HudEXReminderRepeatRule.Frequency
        switch rule.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        @unknown default: return nil
        }
        return HudEXReminderRepeatRule(frequency: frequency, interval: rule.interval)
    }

    private func alarmSignatures(_ alarms: [EKAlarm]) -> [String] {
        alarms.map { alarm in
            if let place = alarm.structuredLocation, let coordinate = place.geoLocation?.coordinate {
                return "geo:\(place.title ?? ""):\(coordinate.latitude):\(coordinate.longitude):\(place.radius):\(alarm.proximity.rawValue)"
            }
            if let date = alarm.absoluteDate { return "at:\(Int(date.timeIntervalSince1970 / 60))" }
            return "offset:\(Int(alarm.relativeOffset))"
        }.sorted()
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
            legacyFingerprint(task),
            task.startDate.map { String(Int($0.timeIntervalSince1970 / 60)) } ?? "",
            task.location ?? "",
            task.locationAlert.map { "\($0.title):\($0.latitude):\($0.longitude):\($0.radiusMeters):\($0.trigger.rawValue)" } ?? "",
            task.repeatRule.map { "\($0.frequency.rawValue):\($0.interval)" } ?? "",
            task.earlyReminderMinutes.map(String.init) ?? ""
        ].joined(separator: "\u{1f}")
        return "v2:" + hash(values)
    }

    private func legacyFingerprint(_ task: HudEXReminder) -> String {
        let values = [
            task.title,
            task.notes ?? "",
            task.dueDate.map { String(Int($0.timeIntervalSince1970 / 60)) } ?? "",
            task.isCompleted ? "1" : "0",
            String(task.priority)
        ].joined(separator: "\u{1f}")
        return hash(values)
    }

    private func hash(_ values: String) -> String {
        var result: UInt64 = 0xcbf29ce484222325
        for byte in values.utf8 {
            result ^= UInt64(byte)
            result &*= 0x100000001b3
        }
        return String(result, radix: 16)
    }
}
