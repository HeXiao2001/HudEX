import DeskHUDCore
import SwiftUI

/// Mini schematic of the screen showing where the two HUD panels sit relative
/// to the Dock. Auto-detects the real Dock side and reflects config changes
/// (panel toggles, background, side-dock text mode) instantly.
struct DockLayoutPreview: View {
    let config: HUDConfig

    private var side: DockSide {
        NSScreen.main.map { DockSide.detect(on: $0) } ?? .bottom
    }

    var body: some View {
        let aspect = NSScreen.main.map { $0.frame.width / $0.frame.height } ?? 1.6
        VStack(spacing: 10) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack(alignment: .topLeading) {
                    // Screen bezel
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.15))
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.6), lineWidth: 1)
                    // Menu bar strip
                    Rectangle()
                        .fill(Color.secondary.opacity(0.28))
                        .frame(width: w, height: max(4, h * 0.045))
                        .padding(3)

                    switch side {
                    case .bottom: bottomDockScene(w: w, h: h)
                    case .left, .right: sideDockScene(w: w, h: h)
                    case .none: noDockScene(w: w, h: h)
                    }
                }
            }
            .aspectRatio(aspect, contentMode: .fit)
            .frame(maxWidth: .infinity)

            legend
        }
        .padding(8)
        .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Bottom Dock

    private func bottomDockScene(w: CGFloat, h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            let bandHeight = h * 0.075
            let bandY = h - bandHeight - h * 0.015
            // Dock
            previewDock(
                rect: CGRect(x: w * 0.30, y: bandY, width: w * 0.40, height: bandHeight),
                horizontal: true
            )
            // Now Queue: left of the Dock
            panelRect(
                CGRect(x: w * 0.025, y: bandY, width: w * 0.24, height: bandHeight),
                anchor: .dockLeft, compact: true
            )
            // Context Card: right of the Dock
            panelRect(
                CGRect(x: w * 0.735, y: bandY, width: w * 0.24, height: bandHeight),
                anchor: .dockRight, compact: true
            )
        }
    }

    // MARK: - Side Dock

    private func sideDockScene(w: CGFloat, h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            let bandWidth = w * 0.075
            let dockHeight = h * 0.45
            let dockY = (h - dockHeight) / 2
            let dockX = side == .left ? w * 0.008 : w - bandWidth - w * 0.008
            // Panels are drawn slightly wider than the Dock band to mirror
            // the `sidePanelExtraWidth` behavior.
            let panelWidth = bandWidth * 1.25
            let panelHeight = h * 0.17
            let gap = h * 0.012
            let panelX = dockX + bandWidth / 2 - panelWidth / 2

            previewDock(
                rect: CGRect(x: dockX, y: dockY, width: bandWidth, height: dockHeight),
                horizontal: false
            )
            if side == .left {
                panelRect(
                    CGRect(x: panelX, y: dockY - gap - panelHeight, width: panelWidth, height: panelHeight),
                    anchor: .dockLeft, compact: false
                )
                panelRect(
                    CGRect(x: panelX, y: dockY + dockHeight + gap, width: panelWidth, height: panelHeight),
                    anchor: .dockRight, compact: false
                )
            } else {
                panelRect(
                    CGRect(x: panelX, y: dockY - gap - panelHeight, width: panelWidth, height: panelHeight),
                    anchor: .dockLeft, compact: false
                )
                panelRect(
                    CGRect(x: panelX, y: dockY + dockHeight + gap, width: panelWidth, height: panelHeight),
                    anchor: .dockRight, compact: false
                )
            }
        }
    }

    // MARK: - No Dock

    private func noDockScene(w: CGFloat, h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            panelRect(
                CGRect(x: w * 0.03, y: h * 0.78, width: w * 0.24, height: h * 0.075),
                anchor: .dockLeft, compact: true
            )
            panelRect(
                CGRect(x: w * 0.73, y: h * 0.78, width: w * 0.24, height: h * 0.075),
                anchor: .dockRight, compact: true
            )
        }
    }

    // MARK: - Pieces

    private func previewDock(rect: CGRect, horizontal: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: rect.height / 4)
                .fill(Color.secondary.opacity(0.45))
            // Icon tiles
            let tiles = 6
            let thickness = min(rect.width, rect.height) * 0.62
            HStack(spacing: thickness * 0.28) {
                ForEach(0 ..< tiles, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: thickness * 0.22)
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: thickness, height: thickness)
                }
            }
            .frame(width: rect.width, height: rect.height)
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }

    /// One HUD panel. Enabled: accent tint (+fill for glass background);
    /// disabled: dashed gray outline. `compact` panels show a single letter;
    /// side panels show vertical text strokes.
    @ViewBuilder
    private func panelRect(_ rect: CGRect, anchor: HUDAnchor, compact: Bool) -> some View {
        let enabled = anchor == .dockLeft ? config.leftPanelEnabled : config.rightPanelEnabled
        ZStack {
            let shape = RoundedRectangle(cornerRadius: min(5, rect.height / 3))
            if enabled {
                if config.backgroundStyle == .glass {
                    shape.fill(Color.accentColor.opacity(0.28))
                }
                shape.strokeBorder(Color.accentColor, lineWidth: 1.5)
                if compact {
                    Text(anchor == .dockLeft ? "Q" : "C")
                        .font(.system(size: min(11, rect.height * 0.6), weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                } else if config.sideDockTextMode == .vertical {
                    // Upright vertical text strokes
                    HStack(spacing: rect.width * 0.16) {
                        ForEach(0 ..< 3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.accentColor.opacity(0.75))
                                .frame(width: rect.width * 0.14, height: rect.height * 0.62)
                        }
                    }
                } else {
                    // Rotated text stroke
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.accentColor.opacity(0.75))
                        .frame(width: rect.width * 0.16, height: rect.height * 0.62)
                }
            } else {
                shape.strokeBorder(
                    Color.secondary.opacity(0.7),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                )
            }
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendDot(color: .secondary, label: tr("Dock"))
            legendDot(color: .accentColor, label: tr("Now Queue"))
            legendDot(color: .accentColor, label: tr("Context Card"))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color.opacity(0.8)).frame(width: 7, height: 7)
            Text(label)
        }
    }
}
