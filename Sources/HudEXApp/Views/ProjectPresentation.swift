import Foundation
import HudEXCore

/// Everything the hover preview needs, pre-computed so the panel can be
/// re-rendered without touching the document store.
struct PreviewSectionModel: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    /// Only the conversation name is shown, never a link or an icon.
    let singleLine: Bool
}

struct PreviewModel: Equatable {
    let projectID: String
    /// The tag's own colours, so the card can look like the same note.
    let role: TagColorRole
    let colorOverride: String?
    let title: String
    let shortTitle: String
    let statusText: String
    let updatedLine: String?
    let relativeAge: String?
    let sections: [PreviewSectionModel]
    let emptyHint: String?

    /// Builds the preview payload for one project.
    static func make(
        project: HudEXProject,
        document: HudEXDocument,
        preferences: Preferences,
        now: Date = Date()
    ) -> PreviewModel {
        // Whatever the file has, in file order: the card is a renderer, not a
        // schema. A project with two sections gets two blocks, one with six
        // gets six (the controller drops the tail if the screen is too small).
        var sections: [PreviewSectionModel] = project.sections
            .filter { !$0.isEmpty }
            .map { section in
                PreviewSectionModel(
                    id: section.id,
                    title: section.title,
                    body: section.body,
                    singleLine: SectionKind.match(section.title) == .latestConversation
                )
            }
        let reminders = document.reminders.filter { $0.projectID == project.id && !$0.isCompleted }
        if !reminders.isEmpty {
            sections.insert(PreviewSectionModel(
                id: "hudex-reminders", title: L10n.t("project.reminders"),
                body: reminders.prefix(3).map(ReminderPresentation.line).joined(separator: "\n")
                    + (reminders.count > 3 ? "\n… +\(reminders.count - 3)" : ""),
                singleLine: false
            ), at: 0)
        }

        let reference = document.ageReferenceDate(for: project)
        let updatedLine: String?
        if preferences.showUpdatedTime {
            if let text = project.updatedAtText, !text.isEmpty {
                updatedLine = L10n.t("time.updatedPrefix", text)
            } else if let date = project.updatedAt {
                updatedLine = L10n.t("time.updatedPrefix", TimestampFormatter.string(from: date))
            } else {
                updatedLine = nil
            }
        } else {
            updatedLine = nil
        }

        return PreviewModel(
            projectID: project.id,
            role: TagColorPolicy.role(
                status: project.status,
                updatedAt: document.ageReferenceDate(for: project),
                now: now,
                thresholds: preferences.colorThresholds
            ),
            colorOverride: project.colorOverride,
            title: project.title,
            shortTitle: project.shortTitle,
            statusText: project.statusDisplayText,
            updatedLine: updatedLine,
            relativeAge: reference.map { RelativeAgeFormatter.string(from: $0, now: now) },
            sections: sections,
            emptyHint: sections.isEmpty ? L10n.t("preview.emptyHint") : nil
        )
    }
}

/// Everything the full project window shows.
struct DetailModel: Equatable {
    let projectID: String
    let title: String
    let statusText: String
    let updatedLine: String?
    let relativeAge: String?
    let preamble: String?
    let sections: [PreviewSectionModel]

    static func make(
        project: HudEXProject,
        document: HudEXDocument,
        preferences: Preferences,
        now: Date = Date()
    ) -> DetailModel {
        let reference = document.ageReferenceDate(for: project)
        let updatedLine: String?
        if let text = project.updatedAtText, !text.isEmpty {
            updatedLine = L10n.t("time.updatedPrefix", text)
        } else if let date = project.updatedAt {
            updatedLine = L10n.t("time.updatedPrefix", TimestampFormatter.string(from: date))
        } else {
            updatedLine = nil
        }

        return DetailModel(
            projectID: project.id,
            title: project.title,
            statusText: project.statusDisplayText,
            updatedLine: updatedLine,
            relativeAge: reference.map { RelativeAgeFormatter.string(from: $0, now: now) },
            preamble: project.preamble,
            sections: project.sections.map {
                PreviewSectionModel(id: $0.id, title: $0.title, body: $0.body, singleLine: false)
            } + ReminderPresentation.section(for: project, document: document)
        )
    }
}

private enum ReminderPresentation {
    static func section(for project: HudEXProject, document: HudEXDocument) -> [PreviewSectionModel] {
        let reminders = document.reminders.filter { $0.projectID == project.id }
        guard !reminders.isEmpty else { return [] }
        return [PreviewSectionModel(
            id: "hudex-reminders", title: L10n.t("project.reminders"),
            body: reminders.map(line).joined(separator: "\n"), singleLine: false
        )]
    }

    static func line(_ reminder: HudEXReminder) -> String {
        var details: [String] = []
        if let date = reminder.dueDate {
            details.append(date.formatted(date: .abbreviated, time: .shortened))
        }
        if let location = reminder.location, !location.isEmpty { details.append("⌖ " + location) }
        else if let alert = reminder.locationAlert { details.append("⌖ " + alert.title) }
        switch reminder.priority {
        case 1: details.append(L10n.t("reminder.priority.high"))
        case 2...5: details.append(L10n.t("reminder.priority.medium"))
        case 6...9: details.append(L10n.t("reminder.priority.low"))
        default: break
        }
        if reminder.isFlagged { details.append("⚑") }
        details.append(contentsOf: reminder.tags.map { "#" + $0 })
        let prefix = reminder.isCompleted ? "✓ " : "○ "
        return prefix + reminder.title + (details.isEmpty ? "" : " · " + details.joined(separator: " · "))
    }
}
