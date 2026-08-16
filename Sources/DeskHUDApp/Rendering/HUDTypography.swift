import DeskHUDCore
import SwiftUI

/// Shared typography and color primitives used by HUD item renderers.
/// All text goes through `HUDText`, which switches between horizontal lines
/// and upright vertical stacking based on the panel's writing mode.
enum HUDTypography {
    enum TextStyle {
        case primary
        case secondary
    }

    static func title(
        for item: HUDItem,
        opacity: Double = 0.85,
        fontSize: Double = 13,
        weight: Font.Weight = .semibold,
        color: Color? = nil
    ) -> some View {
        HUDText(
            text: item.title ?? item.kind ?? item.id,
            fontSize: fontSize,
            weight: weight,
            design: .rounded,
            color: color ?? .white.opacity(opacity)
        )
    }

    @ViewBuilder
    static func optional(
        _ text: String?,
        style: TextStyle,
        opacity: Double = 0.85,
        fontSize: Double = 13,
        color: Color? = nil
    ) -> some View {
        if let text, !text.isEmpty {
            HUDText(
                text: text,
                fontSize: style == .secondary ? fontSize - 2 : fontSize - 1,
                weight: .regular,
                design: .rounded,
                color: color ?? .white.opacity(
                    style == .secondary ? opacity * 0.65 : opacity * 0.8
                )
            )
        }
    }

    /// Small monospaced annotation: times, labels, counters.
    static func mono(
        _ text: String,
        size: Double = 10,
        weight: Font.Weight = .medium,
        color: Color = .white.opacity(0.6)
    ) -> some View {
        HUDText(
            text: text,
            fontSize: size,
            weight: weight,
            design: .monospaced,
            color: color
        )
    }

    /// Plain body line (list items, subtitles).
    static func line(
        _ text: String,
        fontSize: Double,
        weight: Font.Weight = .regular,
        color: Color
    ) -> some View {
        HUDText(
            text: text,
            fontSize: fontSize,
            weight: weight,
            design: .rounded,
            color: color
        )
    }

    static func statusColor(for state: String?) -> Color {
        switch state?.lowercased() {
        case "ok", "ready", "done":    .green
        case "running", "active", "working", "thinking": .cyan
        case "warning", "blocked":     .yellow
        case "error", "failed":        .red
        case "idle", "pending", "todo": .white.opacity(0.35)
        default:                        .white.opacity(0.7)
        }
    }

    static func progressTint(for profile: EffectProfile) -> Color {
        switch profile {
        case .low: .white.opacity(0.82)
        case .medium: .cyan
        case .high: .mint
        }
    }
}
