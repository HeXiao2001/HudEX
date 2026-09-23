import EventKit
import Foundation
import HudEXCore

@MainActor
final class RemindersSyncService {
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

    private let store = EKEventStore()
    private let markerScheme = "hudex-reminder"

    func sync(document: HudEXDocument) async throws -> HudEXDocument {
        guard document.format == .json else {
            throw NSError(domain: "HudEX.Reminders", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Convert the source file to JSON before syncing Reminders."])
        }
        guard try await store.requestFullAccessToReminders() else { throw SyncError.accessDenied }

        let calendars = store.calendars(for: .reminder)
        var updatedProjects: [HudEXProject] = []
        for project in document.projects {
            var calendar = calendars.first { $0.title == listTitle(for: project) }
            if calendar == nil {
                guard let source = store.defaultCalendarForNewReminders()?.source
                        ?? calendars.first(where: { $0.allowsContentModifications })?.source else {
                    throw SyncError.noWritableListSource
                }
                let newCalendar = EKCalendar(for: .reminder, eventStore: store)
                newCalendar.source = source
                newCalendar.title = listTitle(for: project)
                try store.saveCalendar(newCalendar, commit: true)
                calendar = newCalendar
            }
            guard let calendar, calendar.allowsContentModifications else { continue }

            let predicate = store.predicateForReminders(in: [calendar])
            let reminders = await fetchReminders(matching: predicate)
            var byID: [String: EKReminder] = [:]
            for reminder in reminders {
                if let id = taskID(from: reminder.url, projectID: project.id) {
                    byID[id] = reminder
                }
            }
            var tasks = project.reminders
            let nativeOnly = reminders.filter { taskID(from: $0.url, projectID: project.id) == nil }
            for native in nativeOnly {
                let id = UUID().uuidString.lowercased()
                native.url = taskURL(projectID: project.id, taskID: id)
                try store.save(native, commit: true)
                byID[id] = native
                var task = HudEXReminder(
                    id: id, title: native.title, notes: native.notes,
                    dueDate: dueDate(from: native), isCompleted: native.isCompleted,
                    priority: native.priority, reminderIdentifier: native.calendarItemIdentifier,
                    modifiedAt: native.lastModifiedDate ?? Date()
                )
                task.syncFingerprint = fingerprint(task)
                tasks.append(task)
            }

            var retained: [HudEXReminder] = []
            for var task in tasks {
                if let native = byID.removeValue(forKey: task.id) {
                    let nativeDate = native.lastModifiedDate ?? .distantPast
                    let nativeTask = HudEXReminder(
                        id: task.id, title: native.title, notes: native.notes,
                        dueDate: dueDate(from: native), isCompleted: native.isCompleted,
                        priority: native.priority
                    )
                    let fileFingerprint = fingerprint(task)
                    let nativeFingerprint = fingerprint(nativeTask)
                    let fileChanged = task.syncFingerprint.map { $0 != fileFingerprint } ?? true
                    let nativeChanged = task.syncFingerprint.map { $0 != nativeFingerprint } ?? false
                    let fileWins: Bool
                    if fileChanged && nativeChanged {
                        fileWins = (document.fileModifiedAt ?? .distantPast) >= nativeDate
                    } else {
                        fileWins = fileChanged
                    }
                    if nativeChanged && !fileWins {
                        task.title = native.title
                        task.notes = native.notes
                        task.dueDate = dueDate(from: native)
                        task.isCompleted = native.isCompleted
                        task.priority = native.priority
                        task.modifiedAt = nativeDate
                    } else if fileWins {
                        apply(task, to: native, calendar: calendar, projectID: project.id)
                        try store.save(native, commit: true)
                        task.modifiedAt = native.lastModifiedDate ?? Date()
                    }
                    task.reminderIdentifier = native.calendarItemIdentifier
                    task.syncFingerprint = fingerprint(task)
                    retained.append(task)
                } else if task.reminderIdentifier != nil {
                    // A previously synchronized reminder was deleted in Reminders.
                    // EventKit doesn't expose deleted records, so absence is the signal.
                    continue
                } else {
                    let native = EKReminder(eventStore: store)
                    native.calendar = calendar
                    apply(task, to: native, calendar: calendar, projectID: project.id)
                    try store.save(native, commit: true)
                    task.reminderIdentifier = native.calendarItemIdentifier
                    task.modifiedAt = native.lastModifiedDate ?? Date()
                    task.syncFingerprint = fingerprint(task)
                    retained.append(task)
                }
            }

            // Tasks explicitly removed from JSON are removed from this HudEX list.
            for removed in byID.values {
                try store.remove(removed, commit: true)
            }
            updatedProjects.append(HudEXProject(
                id: project.id, title: project.title, shortTitle: project.shortTitle,
                hasExplicitShortTitle: project.hasExplicitShortTitle, status: project.status,
                statusText: project.statusText, updatedAt: project.updatedAt,
                updatedAtText: project.updatedAtText, preamble: project.preamble,
                sections: project.sections, sortOrder: project.sortOrder,
                colorOverride: project.colorOverride, priority: project.priority,
                reminders: retained
            ))
        }

        var updated = document
        updated.projects = updatedProjects
        return updated
    }

    private func fetchReminders(matching predicate: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private func listTitle(for project: HudEXProject) -> String {
        "HudEX · \(project.title) [\(project.id)]"
    }

    private func taskURL(projectID: String, taskID: String) -> URL? {
        URL(string: "\(markerScheme)://\(projectID)/\(taskID)")
    }

    private func taskID(from url: URL?, projectID: String) -> String? {
        guard let url, url.scheme == markerScheme, url.host == projectID else { return nil }
        return url.pathComponents.dropFirst().first
    }

    private func apply(_ task: HudEXReminder, to reminder: EKReminder, calendar: EKCalendar, projectID: String) {
        reminder.title = task.title
        reminder.notes = task.notes
        reminder.calendar = calendar
        reminder.url = taskURL(projectID: projectID, taskID: task.id)
        reminder.priority = min(max(task.priority, 0), 9)
        if let dueDate = task.dueDate {
            var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
            components.calendar = Calendar(identifier: .gregorian)
            components.timeZone = .current
            reminder.dueDateComponents = components
        } else {
            reminder.dueDateComponents = nil
        }
        reminder.isCompleted = task.isCompleted
    }

    private func dueDate(from reminder: EKReminder) -> Date? {
        guard let components = reminder.dueDateComponents else { return nil }
        return Calendar.current.date(from: components)
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
