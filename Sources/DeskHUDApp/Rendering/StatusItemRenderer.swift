import DeskHUDCore
import SwiftUI

final class StatusItemRenderer: HUDItemRenderer {
    let itemType: HUDItemType = .status

    @MainActor
    func body(for item: HUDItem, config: HUDConfig) -> AnyView {
        AnyView(StatusItemBody(item: item, config: config))
    }
}

private struct StatusItemBody: View {
    let item: HUDItem
    let config: HUDConfig

    private var isUrgent: Bool {
        let s = item.state?.lowercased() ?? ""
        return s == "error" || s == "failed" || s == "blocked"
    }

    var body: some View {
        HStack(spacing: 4) {
            if isUrgent {
                Text("‼")
                    .font(.system(size: 11))
            }
            HUDTypography.title(
                for: item,
                opacity: config.window.textOpacity,
                fontSize: config.window.fontSize
            )
            if let label = item.label, !label.isEmpty {
                HUDTypography.mono(
                    label,
                    color: .white.opacity(config.window.textOpacity * 0.6)
                )
            }
        }
    }
}
