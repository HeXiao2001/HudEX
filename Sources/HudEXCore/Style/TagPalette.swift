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

    // MARK: - HSB

    public var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        let delta = maxValue - minValue
        var hue: Double = 0
        if delta > 0 {
            if maxValue == red {
                hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxValue == green {
                hue = (blue - red) / delta + 2
            } else {
                hue = (red - green) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        let saturation = maxValue == 0 ? 0 : delta / maxValue
        return (hue, saturation, maxValue)
    }

    /// Builds a colour from hue/saturation/brightness.
    public static func fromHSB(hue: Double, saturation: Double, brightness: Double) -> PaletteColor {
        let h = (hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
        let c = brightness * saturation
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - c
        let rgb: (Double, Double, Double)
        switch Int(h) {
        case 0: rgb = (c, x, 0)
        case 1: rgb = (x, c, 0)
        case 2: rgb = (0, c, x)
        case 3: rgb = (0, x, c)
        case 4: rgb = (x, 0, c)
        default: rgb = (c, 0, x)
        }
        return PaletteColor(red: rgb.0 + m, green: rgb.1 + m, blue: rgb.2 + m)
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
    /// Pastel paper: the tag's hue at very low saturation and high brightness,
    /// so the card keeps the note's colour while staying light enough for dark
    /// ink. A dark paper with light ink looked muddy and the section headings
    /// disappeared into it.
    public static func paper(for role: TagColorRole, isDark: Bool) -> PaletteColor {
        paper(for: nil, role: role, isDark: isDark)
    }

    public static func paper(for color: PaletteColor?, role: TagColorRole, isDark: Bool) -> PaletteColor {
        let source = color ?? TagPalette.color(for: role, isDark: false)
        let hsb = source.hsb
        return PaletteColor.fromHSB(
            hue: hsb.hue,
            saturation: min(hsb.saturation * 0.30, isDark ? 0.26 : 0.20),
            brightness: isDark ? 0.86 : 0.97
        )
    }

    /// Ruled lines: same hue, a shade deeper than the paper.
    public static func rule(for role: TagColorRole, isDark: Bool, custom: PaletteColor? = nil) -> PaletteColor {
        let paper = self.paper(for: custom, role: role, isDark: isDark)
        let hsb = paper.hsb
        return PaletteColor.fromHSB(
            hue: hsb.hue,
            saturation: min(hsb.saturation + 0.14, 0.45),
            brightness: max(hsb.brightness - (isDark ? 0.10 : 0.07), 0)
        )
    }

    /// Ink for the card: always dark on the pastel paper.
    public static func ink(for role: TagColorRole, isDark: Bool, custom: PaletteColor? = nil) -> PaletteColor {
        let paper = self.paper(for: custom, role: role, isDark: isDark)
        return paper.contrastingTextColor
    }

    /// Softer ink for section headings — readable, but visibly secondary.
    public static func softInk(for role: TagColorRole, isDark: Bool, custom: PaletteColor? = nil) -> PaletteColor {
        let ink = self.ink(for: role, isDark: isDark, custom: custom)
        let paper = self.paper(for: custom, role: role, isDark: isDark)
        return PaletteColor(
            red: (ink.red + paper.red) / 2,
            green: (ink.green + paper.green) / 2,
            blue: (ink.blue + paper.blue) / 2
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

    public func softInk(isDark: Bool) -> PaletteColor {
        PaperPalette.softInk(for: role, isDark: isDark, custom: customColor)
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
