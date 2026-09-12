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
    /// How far the card slides towards the popup while hovered, in points.
    let hoverOffset: Double
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
                    // Rotate around the screen edge so the stack keeps one
                    // straight line instead of fanning out of alignment.
                    .rotationEffect(.degrees(tag.rotationDegrees), anchor: rotationAnchor)
                    .offset(offset(for: tag))
                    .position(x: tag.localFrame.midX, y: tag.localFrame.midY)
                    .zIndex(tag.zIndex)
                    .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.82), value: tag.isHovered)
            }
        }
        .frame(width: max(1, model.size.width), height: max(1, model.size.height))
    }

    /// Tags rest on the screen edge; the hovered one slides towards the popup
    /// — the same direction the card opens in.
    private func offset(for tag: EdgeTagModel) -> CGSize {
        let amount = tag.isHovered ? tag.hoverOffset : 0
        switch model.edge {
        case .left: return CGSize(width: amount, height: 0)
        case .right: return CGSize(width: -amount, height: 0)
        case .bottom: return CGSize(width: 0, height: amount)
        }
    }

    private var rotationAnchor: UnitPoint {
        switch model.edge {
        case .left: return .leading
        case .right: return .trailing
        case .bottom: return .bottom
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
            switch model.style {
            case .skeuomorphic:
                bevel(background)
            case .frosted:
                // A lit edge sells "frosted glass" without a blur pass.
                shape
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.8)
                    .overlay(
                        shape.strokeBorder(Color.black.opacity(0.08), lineWidth: 0.8).offset(y: 0.6)
                    )
            case .minimal:
                shape.strokeBorder(Color(nsColor: background), lineWidth: 1)
            }
            Text(tag.shortTitle)
                .font(.system(size: model.fontSize, weight: .semibold))
                .foregroundStyle(model.style == .minimal ? Color(nsColor: background) : Color(nsColor: foreground))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                // A tag on the bottom edge is tall and narrow, so its label runs
                // up the bookmark instead of being clipped.
                .rotationEffect(.degrees(model.edge == .bottom ? -90 : 0))
                .fixedSize()
            if model.style.usesHoleAndConnector {
                holeTail
                hole
            }
        }
        // Clip the whole card: that is what turns the hole (centred exactly on
        // the edge) into a clean punch mark instead of a circle hanging off the
        // side, and it keeps the bevelled edge tidy.
        .frame(width: tag.size.width, height: tag.size.height)
        .clipShape(shape)
        .scaleEffect(tag.isHovered ? 1.02 : 1.0)
        .accessibilityLabel(Text(tag.title))
        .contextMenu {
            HudEXContextMenu(projectID: tag.id)
        }
    }

    private var shape: RoundedRectangle {
        let radius: CGFloat
        switch model.style {
        case .minimal: radius = 3
        case .frosted: radius = 6
        case .skeuomorphic: radius = 4
        }
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    private func fillColor(_ background: NSColor) -> Color {
        switch model.style {
        case .minimal:
            return .clear
        case .frosted:
            return Color(nsColor: background).opacity(0.88)
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

    /// The punched hole: a full circle, set in from the card-facing edge so it
    /// stays whole. The string is joined to it by a hairline inside the tag
    /// (`holeTail`), which continues into the curve outside.
    private var hole: some View {
        let color = tag.priority?.holeColor(isDark: isDark)
            ?? (isDark ? PaletteColor(hex: "#3C4046")! : PaletteColor(hex: "#FFFFFF")!)
        return Circle()
            .fill(Color(nsColor: EdgeTagStyle.color(color)))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5))
            .frame(width: Self.holeDiameter, height: Self.holeDiameter)
            .offset(holeOffset)
    }

    /// Hairline from the hole's centre to the tag's edge: together with the hole
    /// it covers that gap, so the curve outside looks like it leaves the hole.
    /// It is clipped by the tag, so nothing pokes out.
    private var holeTail: some View {
        let color = PaperPalette.rule(
            for: tag.role,
            isDark: isDark,
            custom: tag.colorOverride.flatMap { TagPalette.color(named: $0, isDark: isDark) }
        )
        return Rectangle()
            .fill(Color(nsColor: EdgeTagStyle.color(color)).opacity(0.85))
            .frame(width: tailLength, height: 1)
            .offset(tailOffset)
    }

    /// How far the hole sits inside the tag.
    static let holeDiameter: CGFloat = 7
    static let holeInset: CGFloat = 6.5

    private var tailLength: CGFloat { Self.holeInset + 0.5 }

    private var tailOffset: CGSize {
        let half = tailLength / 2
        switch model.edge {
        case .left: return CGSize(width: tag.size.width / 2 - half, height: 0)
        case .right: return CGSize(width: -(tag.size.width / 2 - half), height: 0)
        case .bottom: return CGSize(width: 0, height: -(tag.size.height / 2 - half))
        }
    }

    private var holeOffset: CGSize {
        // Inset from the card-facing edge: right for a left-edge tag, left for a
        // right-edge tag, above for a bottom tag.
        let inset = Self.holeInset
        switch model.edge {
        case .left: return CGSize(width: tag.size.width / 2 - inset, height: 0)
        case .right: return CGSize(width: -(tag.size.width / 2 - inset), height: 0)
        case .bottom: return CGSize(width: 0, height: -(tag.size.height / 2 - inset))
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
