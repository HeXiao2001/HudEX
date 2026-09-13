import Foundation

/// How the tags and the hover card are drawn.
///
/// The style changes *appearance* only; the geometry comes from the layout
/// engine and the anchor solver, so every style keeps the same guarantees
/// (never over the Dock, never off screen, always fully visible).
public enum AppearanceStyle: String, Sendable, CaseIterable, Hashable {
    /// Stacked bookmark cards: a hint of depth on the tags and an opaque,
    /// ruled-paper card joined to the tag by a punched hole and a curved line.
    case skeuomorphic
    /// Frosted glass: translucent material so text stays readable on any
    /// background, with soft continuous corners.
    case frosted
    /// Minimal: no fill at all — outlined tags and an outlined card.
    case minimal

    public var displayNameKey: String { "style.\(rawValue)" }

    /// A one-or-two word name, for the preview cards.
    public var shortNameKey: String { "style.\(rawValue).short" }

    public var guideKey: String { "style.\(rawValue).guide" }

    /// The punched hole and its connector line only exist in the skeuomorphic
    /// style; the other three ignore the setting entirely.
    public var usesHoleAndConnector: Bool { self == .skeuomorphic }

    /// Styles whose card is translucent and therefore needs a material.
    public var usesMaterialCard: Bool { self == .frosted }

    /// Decodes a stored value, including styles that were merged away.
    public static func parse(_ raw: String) -> AppearanceStyle? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key == "glass" || key == "liquidglass" || key == "liquid-glass" {
            return .frosted   // merged into the frosted style
        }
        return AppearanceStyle(rawValue: key)
    }

    public static let `default` = AppearanceStyle.skeuomorphic
}

/// How important a project is — drawn as the colour of the punched hole.
///
/// Written in the Markdown file as `优先级：高 / 中 / 低` (or `priority: high`),
/// so an AI can set it while it edits the file.
public enum ProjectPriority: String, Sendable, CaseIterable, Hashable {
    case high
    case normal
    case low

    private static let aliases: [String: ProjectPriority] = [
        "高": .high, "高优先": .high, "重要": .high, "紧急": .high,
        "high": .high, "urgent": .high, "important": .high, "1": .high,
        "中": .normal, "普通": .normal, "一般": .normal, "正常": .normal,
        "normal": .normal, "medium": .normal, "2": .normal,
        "低": .low, "次要": .low, "不急": .low,
        "low": .low, "minor": .low, "3": .low
    ]

    public static func parse(_ raw: String?) -> ProjectPriority? {
        guard let raw else { return nil }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        if let exact = aliases[key] { return exact }
        for (alias, priority) in aliases where key.contains(alias) {
            return priority
        }
        return nil
    }

    public var displayNameKey: String { "priority.\(rawValue)" }

    /// Colour of the hole, as a red/amber/neutral scale.
    public func holeColor(isDark: Bool) -> PaletteColor {
        switch self {
        case .high: return isDark ? PaletteColor(hex: "#D2595B")! : PaletteColor(hex: "#B44A4E")!
        case .normal: return isDark ? PaletteColor(hex: "#8E959F")! : PaletteColor(hex: "#9AA0A8")!
        case .low: return isDark ? PaletteColor(hex: "#5F6875")! : PaletteColor(hex: "#7C838D")!
        }
    }
}
