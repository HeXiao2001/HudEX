import DeskHUDCore
import EventKit

/// Reads today's calendar events and incomplete reminders from macOS Calendar.
/// Returns `[HUDItem]` suitable for direct insertion into an agenda section.
///
/// Items produced here use `cal-`/`rem-` id prefixes so the merge step in
/// AppDelegate can recognize and replace them on re-merge.
@MainActor
enum CalendarReader {
    private static let store = EKEventStore()

    /// Fetch today's events + incomplete reminders as HUDItems.
    /// Requests permissions on first call; silently returns [] if denied.
    static func fetch() async -> [HUDItem] {
        guard await requestAccess() else { return [] }

        let now = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)!

        var items: [HUDItem] = []

        // ── Calendar events ──────────────────────────────────────────
        let eventPredicate = store.predicateForEvents(
            withStart: todayStart, end: todayEnd, calendars: nil
        )
        let events = store.events(matching: eventPredicate)
        for event in events {
            let timeStr: String
            if event.isAllDay {
                timeStr = "all day"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                timeStr = formatter.string(from: event.startDate)
            }
            items.append(HUDItem(
                id: "cal-\(event.eventIdentifier ?? UUID().uuidString)",
                type: .status,
                kind: "event",
                title: event.title ?? "Event",
                label: timeStr,
                state: event.endDate < now ? "done" : "pending"
            ))
        }

        // ── Reminders ────────────────────────────────────────────────
        let reminderPredicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: todayEnd,
            calendars: nil
        )
        let reminders: [EKReminder]? = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: reminderPredicate) { reminders in
                continuation.resume(returning: reminders)
            }
        }
        if let reminders {
            for reminder in reminders {
                items.append(HUDItem(
                    id: "rem-\(reminder.calendarItemIdentifier)",
                    type: .status,
                    kind: "todo",
                    title: reminder.title,
                    label: reminder.dueDateComponents?.date.map { shortTime($0) } ?? nil,
                    state: reminder.isCompleted ? "done" : "pending"
                ))
            }
        }

        // Sort: all-day first, then by time
        items.sort { a, b in
            let aDone = a.state == "done", bDone = b.state == "done"
            if aDone != bDone { return !aDone }          // incomplete first
            return (a.label ?? "") < (b.label ?? "")      // then by time
        }
        return items
    }

    private static func requestAccess() async -> Bool {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        // Reminders access is additive — proceed even if denied
        _ = try? await store.requestFullAccessToReminders()
        return granted
    }

    private static func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
