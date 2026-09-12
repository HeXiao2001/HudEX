import AppKit
import HudEXCore
import SwiftUI

/// Bridges the Core palette into AppKit/SwiftUI colours.
///
/// Everything stays flat and opaque: no gradients, no materials, no shadows.
/// The palette is resolved for the current light/dark appearance, and the label
/// colour is chosen for contrast against whatever background is in use.
enum EdgeTagStyle {
    static func color(_ rgb: PaletteColor) -> NSColor {
        NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }

    /// Background for a tag in the given appearance.
    static func background(role: TagColorRole, colorOverride: String?, isDark: Bool) -> NSColor {
        let appearance = TagAppearanceResolver.appearance(
            role: role,
            colorOverride: colorOverride,
            isDark: isDark
        )
        return color(appearance.background)
    }

    /// Label colour for a tag in the given appearance.
    static func text(role: TagColorRole, colorOverride: String?, isDark: Bool) -> NSColor {
        let appearance = TagAppearanceResolver.appearance(
            role: role,
            colorOverride: colorOverride,
            isDark: isDark
        )
        return color(appearance.text)
    }

    /// Background for the settings legend and any other preview swatch.
    static func backgroundColor(role: TagColorRole, isDark: Bool) -> NSColor {
        color(TagPalette.color(for: role, isDark: isDark))
    }

    static func textColor(role: TagColorRole, isDark: Bool) -> NSColor {
        color(TagPalette.color(for: role, isDark: isDark).contrastingTextColor)
    }
}
