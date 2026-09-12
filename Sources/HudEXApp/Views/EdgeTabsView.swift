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
    /// `优先级：` from the Markdown file, drawn in the punched hole.
    let priority: ProjectPriority?
    let size: CGSize
    /// Frame on screen (AppKit coordinates) — used for hover hit testing.
    let screenFrame: CGRect
    /// Frame inside the panel, in SwiftUI coordinates (top-left origin).
    let localFrame: CGRect
    /// Slant of the stacked look, in degrees.
    let rotationDegrees: Double
    /// Layering into the screen, in points.
    let perpendicularOffset: Double
    let zIndex: Double
    /// True while the pointer is on this tag; drives the small hover lift.
    let isHovered: Bool
}

struct EdgePanelModel: Equatable {
    let edge: DockEdge
    let style: AppearanceStyle
    let fontSize: CGFloat
    /// Frame of the whole panel on screen (AppKit coordinates).
    let screenFrame: CGRect
    /// Panel size, matching `screenFrame`.
    let size: CGSize
    let tags: [EdgeTagModel]

    static func empty(edge: DockEdge) -> EdgePanelModel {
        EdgePanelModel(edge: edge, style: .default, fontSize: 11, screenFrame: .zero, size: .zero, tags: [])
    }
}

/// The tabs of one edge slot.
struct EdgeTabsView: View {
    let model: EdgePanelModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(model.tags) { tag in
                EdgeTabView(tag: tag, model: model)
                    .frame(width: tag.size.width, height: tag.size.height)
                    .rotationEffect(.degrees(tag.rotationDegrees))
                    .offset(offset(for: tag))
                    .position(x: tag.localFrame.midX, y: tag.localFrame.midY)
                    .zIndex(tag.zIndex)
                    .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.82), value: tag.isHovered)
            }
        }
        .frame(width: max(1, model.size.width), height: max(1, model.size.height))
    }

    /// Layered cards sit deeper in the screen; the hovered one swings back out.
    private func offset(for tag: EdgeTagModel) -> CGSize {
        let amount = tag.isHovered ? 0 : tag.perpendicularOffset
        switch model.edge {
        case .left: return CGSize(width: amount, height: 0)
        case .right: return CGSize(width: -amount, height: 0)
        case .bottom: return CGSize(width: 0, height: amount)
        }
    }
}

/// A single tag. The style decides how much of a "card" it looks like — the
/// geometry is identical in every style.
struct EdgeTabView: View {
    let tag: EdgeTagModel
    let model: EdgePanelModel

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        let background = EdgeTagStyle.background(role: tag.role, colorOverride: tag.colorOverride, isDark: isDark)
        let foreground = EdgeTagStyle.text(role: tag.role, colorOverride: tag.colorOverride, isDark: isDark)

        ZStack(alignment: .center) {
            shape.fill(fillColor(background))
            if model.style == .skeuomorphic {
                bevel(background)
            }
            if model.style == .minimal {
                shape.strokeBorder(Color(nsColor: background), lineWidth: 1)
            }
            Text(tag.shortTitle)
                .font(.system(size: model.fontSize, weight: .semibold))
                .foregroundStyle(model.style == .minimal ? Color(nsColor: background) : Color(nsColor: foreground))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 3)
            if model.style.usesHoleAndConnector {
                hole
            }
        }
        .scaleEffect(tag.isHovered ? 1.02 : 1.0)
        .accessibilityLabel(Text(tag.title))
        .contextMenu {
            HudEXContextMenu(projectID: tag.id)
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: model.style == .minimal ? 3 : 4, style: .continuous)
    }

    private func fillColor(_ background: NSColor) -> Color {
        switch model.style {
        case .minimal:
            return .clear
        case .frosted, .glass:
            return Color(nsColor: background).opacity(0.92)
        case .skeuomorphic:
            return Color(nsColor: background)
        }
    }

    /// A hair of depth: one lighter edge inside, one darker edge outside.
    private func bevel(_ background: NSColor) -> some View {
        shape
            .strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.22), Color.black.opacity(0.14)],
                    startPoint: bevelStart,
                    endPoint: bevelEnd
                ),
                lineWidth: 1
            )
    }

    private var bevelStart: UnitPoint {
        switch model.edge {
        case .left: return .topLeading
        case .right: return .topTrailing
        case .bottom: return .top
        }
    }

    private var bevelEnd: UnitPoint {
        switch model.edge {
        case .left: return .bottomTrailing
        case .right: return .bottomLeading
        case .bottom: return .bottom
        }
    }

    /// The punched hole: a small ring whose colour carries the priority.
    private var hole: some View {
        let color = tag.priority?.holeColor(isDark: isDark)
            ?? (isDark ? PaletteColor(hex: "#3C4046")! : PaletteColor(hex: "#FFFFFF")!)
        return Circle()
            .fill(Color(nsColor: EdgeTagStyle.color(color)))
            .frame(width: 7, height: 7)
            .overlay(
                Circle().strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5)
            )
            .offset(holeOffset)
    }

    private var holeOffset: CGSize {
        let inset: CGFloat = 6.5
        switch model.edge {
        case .left: return CGSize(width: tag.size.width / 2 - inset, height: 0)
        case .right: return CGSize(width: -(tag.size.width / 2 - inset), height: 0)
        case .bottom: return CGSize(width: 0, height: tag.size.height / 2 - inset)
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
