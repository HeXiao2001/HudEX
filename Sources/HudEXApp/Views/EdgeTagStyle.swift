import AppKit
import HudEXCore

/// Tag colours: the background *is* the status, so nothing else is drawn.
///
/// Colours are macOS system colours where one exists, they are fully opaque,
/// and they never use gradients, blur, material or transparency.
enum EdgeTagStyle {
    static func backgroundColor(for role: TagColorRole) -> NSColor {
        switch role {
        case .active:
            return .systemGreen
        case .attention:
            return .systemYellow
        case .aging:
            return .systemOrange
        case .stale:
            return .systemGray
        case .paused:
            // Blue-grey, deliberately low saturation.
            return NSColor.systemBlue.blended(withFraction: 0.55, of: .systemGray) ?? .systemBlue
        case .archived:
            return NSColor.systemBlue.blended(withFraction: 0.72, of: .systemGray) ?? .systemGray
        }
    }

    /// Black or white text, whichever contrasts better with the background.
    static func textColor(on background: NSColor) -> NSColor {
        guard let color = background.usingColorSpace(.sRGB) else { return .white }
        let luminance = relativeLuminance(
            red: color.redComponent,
            green: color.greenComponent,
            blue: color.blueComponent
        )
        let contrastWithWhite = (1.05) / (luminance + 0.05)
        let contrastWithBlack = (luminance + 0.05) / 0.05
        return contrastWithBlack >= contrastWithWhite ? .black : .white
    }

    /// WCAG relative luminance.
    static func relativeLuminance(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGFloat {
        func linear(_ component: CGFloat) -> CGFloat {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}
