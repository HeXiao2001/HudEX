import DeskHUDCore
import SwiftUI

final class ListItemRenderer: HUDItemRenderer {
    let itemType: HUDItemType = .list

    @MainActor
    func body(for item: HUDItem, config: HUDConfig) -> AnyView {
        AnyView(ListItemBody(item: item, config: config))
    }
}

private struct ListItemBody: View {
    let item: HUDItem
    let config: HUDConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HUDTypography.title(for: item, opacity: config.window.textOpacity, fontSize: config.window.fontSize)
            ForEach(
                Array((item.lines ?? []).prefix(config.window.maxLines).enumerated()),
                id: \.offset
            ) { _, line in
                HUDTypography.line(
                    line,
                    fontSize: 12,
                    color: .white.opacity(config.window.textOpacity * 0.7)
                )
            }
        }
    }
}
