import HudEXCore
import SwiftUI

/// A miniature of the screen showing where the bookmarks will actually land.
///
/// It is drawn by running the real layout engine against a pretend screen, so
/// the picture cannot drift away from the behaviour it describes — the thing a
/// list of radio buttons could never show.
struct LayoutDiagram: View {
    let mode: LayoutMode
    let metrics: TabMetrics
    let dock: DockBounds
    let projectCount: Int
    let isDark: Bool

    /// A screen-shaped stage; its long side is the one the Dock sits on.
    private var stage: ScreenBounds {
        switch dock.edge {
        case .left, .right:
            return ScreenBounds(
                frame: CGRect(x: 0, y: 0, width: 560, height: 340),
                visibleFrame: CGRect(x: dock.isPresent ? 62 : 0, y: 0, width: dock.isPresent ? 498 : 560, height: 340)
            )
        case .bottom:
            return ScreenBounds(
                frame: CGRect(x: 0, y: 0, width: 720, height: 300),
                visibleFrame: CGRect(x: 0, y: dock.isPresent ? 58 : 0, width: 720, height: dock.isPresent ? 242 : 300)
            )
        }
    }

    private var plan: EdgeLayoutPlan {
        EdgeLayoutEngine.plan(
            projectCount: projectCount,
            metrics: metrics,
            screen: stage,
            dock: dock,
            mode: mode
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = min(
                geometry.size.width / stage.frame.width,
                geometry.size.height / stage.frame.height
            )
            // Everything below is positioned inside this stage-sized box, which
            // is then centred in the row — forgetting that offset is what put
            // the bookmarks outside the screen the first time round.
            let stageSize = CGSize(
                width: stage.frame.width * scale,
                height: stage.frame.height * scale
            )

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(isDark ? 0.10 : 0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                    )
                    .frame(width: stageSize.width, height: stageSize.height)

                if dock.isPresent {
                    dockShape(scale: scale)
                }

                ForEach(Array(plan.placements.enumerated()), id: \.offset) { index, placement in
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(Color.accentColor.opacity(index == 0 ? 0.95 : 0.5))
                        .frame(
                            width: max(2, placement.frame.width * scale),
                            height: max(2, placement.frame.height * scale)
                        )
                        .position(
                            x: placement.frame.midX * scale,
                            y: (stage.frame.height - placement.frame.midY) * scale
                        )
                }
            }
            .frame(width: stageSize.width, height: stageSize.height, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func dockShape(scale: CGFloat) -> some View {
        let thickness = dock.thickness
        let dockLength = min(120, max(40, dock.occupiedEnd - dock.occupiedStart))
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.20))
            .frame(
                width: (dock.edge == .bottom ? dockLength : thickness) * scale,
                height: (dock.edge == .bottom ? thickness : dockLength) * scale
            )
            .position(position(thickness: thickness, length: dockLength, scale: scale))
    }

    /// Roughly where the real Dock would sit on this stage.
    private func position(thickness: CGFloat, length: CGFloat, scale: CGFloat) -> CGPoint {
        let stageW = stage.frame.width * scale
        let stageH = stage.frame.height * scale
        let t = thickness * scale
        let l = length * scale
        switch dock.edge {
        case .left: return CGPoint(x: t / 2, y: stageH - l / 2 - 20 * scale)
        case .right: return CGPoint(x: stageW - t / 2, y: stageH - l / 2 - 20 * scale)
        case .bottom: return CGPoint(x: 30 * scale + l / 2, y: stageH - t / 2)
        }
    }
}

/// One plain sentence describing the same plan, updated as the controls change.
enum LayoutSummary {
    static func text(mode: LayoutMode, edge: DockEdge, capacity: Int, overflow: Int) -> String {
        let edgeName = L10n.t(edgeNameKey(edge))
        let phrase = L10n.t(anchorNameKey(mode, edge: edge))
        if overflow > 0 {
            return L10n.t("layout.summary.overflow", edgeName, phrase, capacity, overflow)
        }
        return L10n.t("layout.summary", edgeName, phrase)
    }

    private static func edgeNameKey(_ edge: DockEdge) -> String {
        switch edge {
        case .left: return "layout.summary.edge.left"
        case .right: return "layout.summary.edge.right"
        case .bottom: return "layout.summary.edge.bottom"
        }
    }

    private static func anchorNameKey(_ mode: LayoutMode, edge: DockEdge) -> String {
        switch mode.kind {
        case .dockAdaptive: return "layout.summary.dockAdaptive"
        case .dockSplit: return "layout.summary.dockSplit"
        case .fixedEdge:
            switch mode.anchor {
            case .start: return "layout.anchor.start"
            case .center: return "layout.anchor.center"
            case .end: return "layout.anchor.end"
            }
        }
    }
}
