import DeskHUDCore
import SwiftUI

final class ProgressItemRenderer: HUDItemRenderer {
    let itemType: HUDItemType = .progress

    @MainActor
    func body(for item: HUDItem, config: HUDConfig) -> AnyView {
        AnyView(ProgressItemBody(item: item, config: config))
    }
}

private struct ProgressItemBody: View {
    let item: HUDItem
    let config: HUDConfig

    @Environment(\.hudVerticalText) private var vertical

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                HUDTypography.title(for: item, opacity: config.window.textOpacity, fontSize: config.window.fontSize)
                Spacer(minLength: 8)
                HUDTypography.optional(item.label, style: .secondary, opacity: config.window.textOpacity, fontSize: config.window.fontSize)
            }
            if vertical {
                // Vertical capsule track — a horizontal bar reads as a
                // broken slider inside a narrow vertical panel.
                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 4, height: 34)
                    .overlay(alignment: .bottom) {
                        Capsule()
                            .fill(HUDTypography.progressTint(for: config.effectProfile))
                            .frame(width: 4, height: max(2, 34 * CGFloat(clamped)))
                    }
            } else {
                ProgressView(value: clamped)
                    .progressViewStyle(.linear)
                    .tint(HUDTypography.progressTint(for: config.effectProfile))
            }
        }
    }

    private var clamped: Double {
        min(max(item.value ?? 0, 0), 1)
    }
}
