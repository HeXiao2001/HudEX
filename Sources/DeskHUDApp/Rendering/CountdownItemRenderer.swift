import DeskHUDCore
import SwiftUI

/// Shows time remaining until a scheduled event.
/// Uses `label` for precomputed text (e.g. "in 12m"), `time` for the event time.
final class CountdownItemRenderer: HUDItemRenderer {
    let itemType: HUDItemType = .countdown

    @MainActor
    func body(for item: HUDItem, config: HUDConfig) -> AnyView {
        AnyView(CountdownItemBody(item: item, config: config))
    }
}

private struct CountdownItemBody: View {
    let item: HUDItem
    let config: HUDConfig

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                HUDTypography.title(for: item,
                                    opacity: config.window.textOpacity,
                                    fontSize: config.window.fontSize)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    HUDTypography.optional(
                        subtitle,
                        style: .secondary,
                        opacity: config.window.textOpacity,
                        fontSize: config.window.fontSize
                    )
                }
            }
            Spacer(minLength: 4)
            if let label = item.label, !label.isEmpty {
                HUDTypography.mono(
                    label,
                    size: config.window.fontSize - 1,
                    weight: .semibold,
                    color: countdownColor
                )
            }
        }
    }

    private var countdownColor: Color {
        switch item.state?.lowercased() {
        case "error", "failed":  .red
        case "warning":          .yellow
        case "running", "active": .cyan
        default:                  .white.opacity(0.8)
        }
    }
}
