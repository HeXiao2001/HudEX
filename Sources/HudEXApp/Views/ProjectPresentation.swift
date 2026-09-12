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
        var sections: [PreviewSectionModel] = []

        if let current = project.currentSection, !current.isEmpty {
            sections.append(
                PreviewSectionModel(id: current.id, title: current.title, body: current.body, singleLine: false)
            )
        }
        if let next = project.nextSection, !next.isEmpty {
            sections.append(
                PreviewSectionModel(id: next.id, title: next.title, body: next.body, singleLine: false)
            )
        }
        if let conversation = project.latestConversationSection, !conversation.isEmpty {
            sections.append(
                PreviewSectionModel(
                    id: conversation.id,
                    title: conversation.title,
                    body: conversation.body,
                    singleLine: true
                )
            )
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
            }
        )
    }
}
