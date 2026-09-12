import Foundation

/// A plain sRGB colour, used so the palette and its contrast rules live in
/// testable code instead of being scattered through views.
public struct PaletteColor: Sendable, Equatable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(
            red: Double((value & 0xFF0000) >> 16) / 255,
            green: Double((value & 0x00FF00) >> 8) / 255,
            blue: Double(value & 0x0000FF) / 255
        )
    }

    public var hexString: String {
        String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    /// Same colour at a different opacity (the paper grain and rules use it).
    public func withAlpha(_ alpha: Double) -> PaletteColor {
        self
    }

    /// WCAG relative luminance.
    public var luminance: Double {
        func linear(_ component: Double) -> Double {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// Black or white, whichever contrasts better.
    public var contrastingTextColor: PaletteColor {
        let withWhite = 1.05 / (luminance + 0.05)
        let withBlack = (luminance + 0.05) / 0.05
        return withBlack >= withWhite ? PaletteColor(red: 0, green: 0, blue: 0) : PaletteColor(red: 1, green: 1, blue: 1)
    }

    public var contrastRatioAgainstBlack: Double { (luminance + 0.05) / 0.05 }
    public var contrastRatioAgainstWhite: Double { 1.05 / (luminance + 0.05) }
}

/// The tag palette.
///
/// Colours are deliberately muted rather than the raw system hues: the tag is a
/// solid bookmark, so a slightly desaturated tone reads as "designed" instead
/// of "alert". Everything is opaque, flat and cheap to draw.
public enum TagPalette {
    public static func color(for role: TagColorRole, isDark: Bool) -> PaletteColor {
        switch role {
        case .active:
            return isDark ? PaletteColor(hex: "#4FAE74")! : PaletteColor(hex: "#3E8E5A")!
        case .attention:
            return isDark ? PaletteColor(hex: "#D9AE4A")! : PaletteColor(hex: "#C39A2E")!
        case .aging:
            return isDark ? PaletteColor(hex: "#CE8B57")! : PaletteColor(hex: "#B7743F")!
        case .stale:
            return isDark ? PaletteColor(hex: "#7E858F")! : PaletteColor(hex: "#8B9099")!
        case .paused:
            return isDark ? PaletteColor(hex: "#6C81A0")! : PaletteColor(hex: "#5C7089")!
        case .archived:
            return isDark ? PaletteColor(hex: "#5F6875")! : PaletteColor(hex: "#767E8A")!
        }
    }

    /// Named colours an AI or a user can write in the Markdown file.
    private static let named: [String: (light: String, dark: String)] = [
        "green": ("#3E8E5A", "#4FAE74"),
        "绿": ("#3E8E5A", "#4FAE74"),
        "绿色": ("#3E8E5A", "#4FAE74"),
        "yellow": ("#C39A2E", "#D9AE4A"),
        "黄": ("#C39A2E", "#D9AE4A"),
        "黄色": ("#C39A2E", "#D9AE4A"),
        "amber": ("#C39A2E", "#D9AE4A"),
        "orange": ("#B7743F", "#CE8B57"),
        "橙": ("#B7743F", "#CE8B57"),
        "橙色": ("#B7743F", "#CE8B57"),
        "red": ("#B45B54", "#C9726A"),
        "红": ("#B45B54", "#C9726A"),
        "红色": ("#B45B54", "#C9726A"),
        "gray": ("#8B9099", "#7E858F"),
        "grey": ("#8B9099", "#7E858F"),
        "灰": ("#8B9099", "#7E858F"),
        "灰色": ("#8B9099", "#7E858F"),
        "blue": ("#4C6FA0", "#6288BC"),
        "蓝": ("#4C6FA0", "#6288BC"),
        "蓝色": ("#4C6FA0", "#6288BC"),
        "bluegray": ("#5C7089", "#6C81A0"),
        "蓝灰": ("#5C7089", "#6C81A0"),
        "teal": ("#3E8B8B", "#4FA5A5"),
        "青": ("#3E8B8B", "#4FA5A5"),
        "purple": ("#7A5F9E", "#9276B8"),
        "紫": ("#7A5F9E", "#9276B8"),
        "紫色": ("#7A5F9E", "#9276B8"),
        "pink": ("#B0698A", "#C9839F"),
        "粉": ("#B0698A", "#C9839F")
    ]

    /// Resolves a colour name or `#RRGGBB` value written in the Markdown file.
    public static func color(named name: String, isDark: Bool) -> PaletteColor? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key.hasPrefix("#"), let hex = PaletteColor(hex: key) { return hex }

        if let entry = named[key] {
            return PaletteColor(hex: isDark ? entry.dark : entry.light)
        }
        // "浅绿" / "深蓝" style prefixes are ignored, the base colour is used.
        for (name, entry) in named where key.hasSuffix(name) {
            return PaletteColor(hex: isDark ? entry.dark : entry.light)
        }
        return nil
    }

    /// Colour names offered in the settings documentation.
    public static var documentedColorNames: [String] {
        ["green", "yellow", "amber", "orange", "red", "gray", "blue", "bluegray", "teal", "purple", "pink"]
    }
}

/// Paper for the skeuomorphic card: the tag's own colour, mixed into a warm
/// paper base so the card reads as "the same note" rather than a grey box.
public enum PaperPalette {
    public static func paper(for role: TagColorRole, isDark: Bool) -> PaletteColor {
        blend(TagPalette.color(for: role, isDark: isDark), into: base(isDark: isDark), amount: isDark ? 0.16 : 0.14)
    }

    public static func paper(for color: PaletteColor?, role: TagColorRole, isDark: Bool) -> PaletteColor {
        guard let color else { return paper(for: role, isDark: isDark) }
        return blend(color, into: base(isDark: isDark), amount: isDark ? 0.16 : 0.14)
    }

    /// Ruled lines: a touch darker than the paper.
    public static func rule(for role: TagColorRole, isDark: Bool, custom: PaletteColor? = nil) -> PaletteColor {
        let paper = custom.map { self.paper(for: $0, role: role, isDark: isDark) } ?? paper(for: role, isDark: isDark)
        return blend(isDark ? PaletteColor(hex: "#000000")! : PaletteColor(hex: "#8A7B58")!, into: paper, amount: isDark ? 0.22 : 0.16)
    }

    public static func ink(for role: TagColorRole, isDark: Bool, custom: PaletteColor? = nil) -> PaletteColor {
        let paper = custom.map { self.paper(for: $0, role: role, isDark: isDark) } ?? paper(for: role, isDark: isDark)
        return paper.contrastingTextColor
    }

    private static func base(isDark: Bool) -> PaletteColor {
        isDark ? PaletteColor(hex: "#1E1E22")! : PaletteColor(hex: "#FDFAF2")!
    }

    /// Mixes `color` into `base`, keeping `amount` of the original colour.
    private static func blend(_ color: PaletteColor, into base: PaletteColor, amount: Double) -> PaletteColor {
        PaletteColor(
            red: base.red + (color.red - base.red) * amount,
            green: base.green + (color.green - base.green) * amount,
            blue: base.blue + (color.blue - base.blue) * amount
        )
    }
}

/// The resolved look of one tag.
public struct TagAppearance: Sendable, Equatable {
    public var role: TagColorRole
    public var background: PaletteColor
    public var text: PaletteColor
    /// True when the project carries its own colour in the Markdown file.
    public var isCustom: Bool
    /// The project's own colour, when it has one.
    public var customColor: PaletteColor?

    public init(
        role: TagColorRole,
        background: PaletteColor,
        text: PaletteColor,
        isCustom: Bool,
        customColor: PaletteColor? = nil
    ) {
        self.role = role
        self.background = background
        self.text = text
        self.isCustom = isCustom
        self.customColor = customColor
    }

    /// Paper for the skeuomorphic card, tinted by this tag's own colour.
    public func paper(isDark: Bool) -> PaletteColor {
        PaperPalette.paper(for: customColor, role: role, isDark: isDark)
    }

    public func rule(isDark: Bool) -> PaletteColor {
        PaperPalette.rule(for: role, isDark: isDark, custom: customColor)
    }

    public func ink(isDark: Bool) -> PaletteColor {
        PaperPalette.ink(for: role, isDark: isDark, custom: customColor)
    }
}

public enum TagAppearanceResolver {
    /// Resolves the final colours for a project.
    ///
    /// - Parameter colorOverride: `颜色：` from the Markdown file, either a
    ///   palette name or a `#RRGGBB` value.
    public static func appearance(
        role: TagColorRole,
        colorOverride: String?,
        isDark: Bool
    ) -> TagAppearance {
        if let colorOverride, let custom = TagPalette.color(named: colorOverride, isDark: isDark) {
            return TagAppearance(
                role: role,
                background: custom,
                text: custom.contrastingTextColor,
                isCustom: true,
                customColor: custom
            )
        }
        let background = TagPalette.color(for: role, isDark: isDark)
        return TagAppearance(
            role: role,
            background: background,
            text: background.contrastingTextColor,
            isCustom: false
        )
    }
}
