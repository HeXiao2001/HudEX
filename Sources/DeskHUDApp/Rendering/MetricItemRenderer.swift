import DeskHUDCore
import SwiftUI

final class MetricItemRenderer: HUDItemRenderer {
    let itemType: HUDItemType = .metric

    @MainActor
    func body(for item: HUDItem, config: HUDConfig) -> AnyView {
        AnyView(MetricItemBody(item: item, config: config))
    }
}

private struct MetricItemBody: View {
    let item: HUDItem
    let config: HUDConfig

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            HUDTypography.title(for: item, opacity: config.window.textOpacity, fontSize: config.window.fontSize)
            if let value = item.value {
                HUDTypography.line(
                    value.formatted(.number.precision(.fractionLength(0...1))),
                    fontSize: 22,
                    weight: .semibold,
                    color: .white.opacity(config.window.textOpacity)
                )
                HUDTypography.optional(item.unit, style: .secondary, opacity: config.window.textOpacity, fontSize: config.window.fontSize)
            }
        }
    }
}
