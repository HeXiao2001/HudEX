import HudEXCore
import SwiftUI

/// Value types handed to SwiftUI. Panels are re-rendered by replacing these
/// values, which keeps the view tree small and free of observation cycles.
struct EdgeTagModel: Identifiable, Equatable {
    let id: String
    let index: Int
    let shortTitle: String
    let title: String
    let role: TagColorRole
    /// `颜色：` from the Markdown file, when the project overrides the palette.
    let colorOverride: String?
    let size: CGSize
    /// Frame on screen (AppKit coordinates) — used for hover hit testing.
    let screenFrame: CGRect
    /// Frame inside the panel, in SwiftUI coordinates (top-left origin).
    let localFrame: CGRect
    /// Slant of the stacked look, in degrees.
    let rotationDegrees: Double
    /// Perpendicular layer offset, in points.
    let stagger: Double
    let zIndex: Double
    /// True while the pointer is on this tag; drives the small hover lift.
    let isHovered: Bool
}

struct EdgePanelModel: Equatable {
    let edge: DockEdge
    let fontSize: CGFloat
    /// Frame of the whole panel on screen (AppKit coordinates).
    let screenFrame: CGRect
    /// Panel size, matching `screenFrame`.
    let size: CGSize
    let tags: [EdgeTagModel]

    static func empty(edge: DockEdge) -> EdgePanelModel {
        EdgePanelModel(edge: edge, fontSize: 11, screenFrame: .zero, size: .zero, tags: [])
    }
}

/// The tabs of one edge slot.
struct EdgeTabsView: View {
    let model: EdgePanelModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(model.tags) { tag in
                EdgeTabView(tag: tag, fontSize: model.fontSize, edge: model.edge)
                    .frame(width: tag.size.width, height: tag.size.height)
                    .rotationEffect(.degrees(tag.rotationDegrees))
                    .offset(
                        x: model.edge == .bottom ? 0 : (tag.isHovered ? -tag.stagger : tag.stagger),
                        y: model.edge == .bottom ? (tag.isHovered ? tag.stagger : -tag.stagger) : 0
                    )
                    .position(x: tag.localFrame.midX, y: tag.localFrame.midY)
                    .zIndex(tag.zIndex)
                    .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.82), value: tag.isHovered)
            }
        }
        .frame(width: max(1, model.size.width), height: max(1, model.size.height))
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
}

/// A single solid-colour bookmark.
///
/// Hovering lifts the tag slightly out of the stack — the size never changes,
/// and the animation only runs while the pointer moves between tags.
struct EdgeTabView: View {
    let tag: EdgeTagModel
    let fontSize: CGFloat
    let edge: DockEdge

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        let background = EdgeTagStyle.background(role: tag.role, colorOverride: tag.colorOverride, isDark: isDark)
        let foreground = EdgeTagStyle.text(role: tag.role, colorOverride: tag.colorOverride, isDark: isDark)

        Text(tag.shortTitle)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(Color(nsColor: foreground))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(Color(nsColor: background))
            )
            .scaleEffect(tag.isHovered ? 1.02 : 1.0)
            .accessibilityLabel(Text(tag.title))
            .contextMenu {
                HudEXContextMenu(projectID: tag.id)
            }
    }
}

/// Native context menu on a tag. This is also the recovery path when the Menu
/// Bar icon has been switched off.
struct HudEXContextMenu: View {
    let projectID: String?
    @ObservedObject private var controller = HudEXController.shared
    @ObservedObject private var preferences = Preferences.shared

    var body: some View {
        if let projectID {
            Button(L10n.t("context.openDetail")) { controller.openDetail(projectID: projectID) }
        }
        Button(L10n.t("context.openMarkdown")) { controller.openMarkdownFile() }
        Button(L10n.t("menu.reload")) { controller.reloadDocument() }

        Divider()

        Toggle(L10n.t("menu.showTags"), isOn: Binding(
            get: { preferences.showTags },
            set: { preferences.showTags = $0 }
        ))
        Toggle(L10n.t("menu.showMenuBarIcon"), isOn: Binding(
            get: { preferences.showMenuBarIcon },
            set: { preferences.showMenuBarIcon = $0 }
        ))

        Button(L10n.t("menu.settings")) { controller.openSettings() }
            .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button(L10n.t("menu.quit")) { controller.quit() }
            .keyboardShortcut("q", modifiers: .command)
    }
}
