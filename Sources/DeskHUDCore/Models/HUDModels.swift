import Foundation

public struct HUDConfig: Codable, Equatable, Sendable {
    public var version: Int
    public var effectProfile: EffectProfile
    public var fullscreenMode: FullscreenMode
    public var displays: DisplayMode
    public var fixedDisplayID: UInt32?
    public var backgroundStyle: BackgroundStyle
    public var sideDockTextMode: SideDockTextMode
    public var leftPanelEnabled: Bool
    public var rightPanelEnabled: Bool
    public var window: HUDWindowConfig
    public var calendarEvents: Bool
    public var launchAtLogin: Bool
    public var hideMenuBar: Bool
    public var watchDirectory: String?
    public var debugLogging: Bool

    public init(
        version: Int = 1,
        effectProfile: EffectProfile = .low,
        fullscreenMode: FullscreenMode = .desktopOnly,
        displays: DisplayMode = .primary,
        fixedDisplayID: UInt32? = nil,
        backgroundStyle: BackgroundStyle = .glass,
        sideDockTextMode: SideDockTextMode = .vertical,
        leftPanelEnabled: Bool = true,
        rightPanelEnabled: Bool = true,
        calendarEvents: Bool = false,
        launchAtLogin: Bool = false,
        hideMenuBar: Bool = false,
        watchDirectory: String? = nil,
        window: HUDWindowConfig = HUDWindowConfig(),
        debugLogging: Bool = true
    ) {
        self.version = version
        self.effectProfile = effectProfile
        self.fullscreenMode = fullscreenMode
        self.displays = displays
        self.fixedDisplayID = fixedDisplayID
        self.backgroundStyle = backgroundStyle
        self.sideDockTextMode = sideDockTextMode
        self.leftPanelEnabled = leftPanelEnabled
        self.rightPanelEnabled = rightPanelEnabled
        self.calendarEvents = calendarEvents
        self.launchAtLogin = launchAtLogin
        self.hideMenuBar = hideMenuBar
        self.watchDirectory = watchDirectory
        self.window = window
        self.debugLogging = debugLogging
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case effectProfile
        case fullscreenMode
        case displays
        case fixedDisplayID
        case backgroundStyle
        case sideDockTextMode
        case leftPanelEnabled
        case rightPanelEnabled
        case window
        case calendarEvents
        case launchAtLogin
        case hideMenuBar
        case watchDirectory
        case debugLogging
    }

    public init(from decoder: Decoder) throws {
        let defaults = HUDConfig()
        let container = try decoder.container(keyedBy: CodingKeys.self)

        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? defaults.version
        effectProfile = try container.decodeIfPresent(EffectProfile.self, forKey: .effectProfile) ?? defaults.effectProfile
        fullscreenMode = try container.decodeIfPresent(FullscreenMode.self, forKey: .fullscreenMode) ?? defaults.fullscreenMode
        displays = try container.decodeIfPresent(DisplayMode.self, forKey: .displays) ?? defaults.displays
        fixedDisplayID = try container.decodeIfPresent(UInt32.self, forKey: .fixedDisplayID) ?? defaults.fixedDisplayID
        backgroundStyle = try container.decodeIfPresent(BackgroundStyle.self, forKey: .backgroundStyle) ?? defaults.backgroundStyle
        sideDockTextMode = try container.decodeIfPresent(SideDockTextMode.self, forKey: .sideDockTextMode) ?? defaults.sideDockTextMode
        leftPanelEnabled = try container.decodeIfPresent(Bool.self, forKey: .leftPanelEnabled) ?? defaults.leftPanelEnabled
        rightPanelEnabled = try container.decodeIfPresent(Bool.self, forKey: .rightPanelEnabled) ?? defaults.rightPanelEnabled
        window = try container.decodeIfPresent(HUDWindowConfig.self, forKey: .window) ?? defaults.window
        calendarEvents = try container.decodeIfPresent(Bool.self, forKey: .calendarEvents) ?? defaults.calendarEvents
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        hideMenuBar = try container.decodeIfPresent(Bool.self, forKey: .hideMenuBar) ?? defaults.hideMenuBar
        watchDirectory = try container.decodeIfPresent(String.self, forKey: .watchDirectory) ?? defaults.watchDirectory
        debugLogging = try container.decodeIfPresent(Bool.self, forKey: .debugLogging) ?? defaults.debugLogging
    }
}

public enum FullscreenMode: String, Codable, CaseIterable, Sendable {
    case overlay
    case desktopOnly
}

public enum BackgroundStyle: String, Codable, CaseIterable, Sendable {
    case clear  // No background, only text and glyphs
    case glass  // Native Liquid Glass (NSGlassEffectView on macOS 26+, vibrancy fallback)

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "clear", "glass":
            self = BackgroundStyle(rawValue: raw)!
        case "dark":  // legacy value from pre-glass builds
            self = .clear
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported backgroundStyle: \(raw). Supported: clear, glass."
                )
            )
        }
    }
}

public enum DisplayMode: String, Codable, CaseIterable, Sendable {
    case all
    case primary
    case mouse
    case fixed
    case main  // deprecated, maps to primary in HUDDisplayResolver
}

/// Text strategy for side-edge Docks with a narrow band (auto-applies only
/// when the band is too narrow for horizontal text):
/// - `vertical`: upright CJK-style stacking, columns right-to-left (default,
///   Chinese-friendly — "two lines" become "two columns")
/// - `rotated`: whole panel rotated 90°; reads sideways — best for Latin
///   content only
public enum SideDockTextMode: String, Codable, CaseIterable, Sendable {
    case vertical
    case rotated
}

public struct HUDWindowConfig: Codable, Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var margin: Double
    public var cornerRadius: Double
    public var opacity: Double
    public var maxLines: Int
    public var contentDensity: ContentDensity
    public var fontSize: Double
    public var textOpacity: Double
    public var scrollIntervalSeconds: Double
    public var leftPresentation: HUDPresentation
    public var rightPresentation: HUDPresentation

    public init(
        width: Double = 0,   // 0 = auto-fill available space
        height: Double = 82,
        margin: Double = 18,
        cornerRadius: Double = 14,
        opacity: Double = 0.82,
        fontSize: Double = 13,
        maxLines: Int = 1,
        textOpacity: Double = 0.85,
        contentDensity: ContentDensity = .comfortable,
        scrollIntervalSeconds: Double = 4,
        leftPresentation: HUDPresentation = .pagerRail,
        rightPresentation: HUDPresentation = .stack
    ) {
        self.width = width
        self.height = height
        self.margin = margin
        self.cornerRadius = cornerRadius
        self.opacity = opacity
        self.fontSize = fontSize
        self.maxLines = maxLines
        self.textOpacity = textOpacity
        self.contentDensity = contentDensity
        self.scrollIntervalSeconds = scrollIntervalSeconds
        self.leftPresentation = leftPresentation
        self.rightPresentation = rightPresentation
    }

    private enum CodingKeys: String, CodingKey {
        case width
        case height
        case margin
        case cornerRadius
        case opacity
        case maxLines
        case contentDensity
        case fontSize
        case textOpacity
        case scrollIntervalSeconds
        case leftPresentation
        case rightPresentation
    }

    public init(from decoder: Decoder) throws {
        let defaults = HUDWindowConfig()
        let container = try decoder.container(keyedBy: CodingKeys.self)

        width = try container.decodeIfPresent(Double.self, forKey: .width) ?? defaults.width
        height = try container.decodeIfPresent(Double.self, forKey: .height) ?? defaults.height
        margin = try container.decodeIfPresent(Double.self, forKey: .margin) ?? defaults.margin
        cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? defaults.cornerRadius
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? defaults.opacity
        maxLines = try container.decodeIfPresent(Int.self, forKey: .maxLines) ?? defaults.maxLines
        contentDensity = try container.decodeIfPresent(ContentDensity.self, forKey: .contentDensity) ?? defaults.contentDensity
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? defaults.fontSize
        textOpacity = try container.decodeIfPresent(Double.self, forKey: .textOpacity) ?? defaults.textOpacity
        scrollIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .scrollIntervalSeconds) ?? defaults.scrollIntervalSeconds
        leftPresentation = try container.decodeIfPresent(HUDPresentation.self, forKey: .leftPresentation) ?? defaults.leftPresentation
        rightPresentation = try container.decodeIfPresent(HUDPresentation.self, forKey: .rightPresentation) ?? defaults.rightPresentation
    }
}

public enum ContentDensity: String, Codable, Sendable {
    case compact
    case comfortable
    case spacious
}

public enum HUDPresentation: String, Codable, CaseIterable, Sendable {
    case stack
    case pagerRail
    case minimal
}

public struct HUDDocument: Codable, Equatable, Sendable {
    public var version: Int
    public var slots: [HUDSlot]

    public init(version: Int = 1, slots: [HUDSlot]) {
        self.version = version
        self.slots = slots
    }
}

public struct HUDSection: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String?
    public var items: [HUDItem]

    public init(id: String, title: String? = nil, items: [HUDItem]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

public struct HUDSlot: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var anchor: HUDAnchor
    public var rotation: HUDRotation
    public var sections: [HUDSection]?
    public var items: [HUDItem]

    public init(
        id: String,
        anchor: HUDAnchor,
        rotation: HUDRotation = HUDRotation(),
        sections: [HUDSection]? = nil,
        items: [HUDItem]
    ) {
        self.id = id
        self.anchor = anchor
        self.rotation = rotation
        self.sections = sections
        self.items = items
    }

    /// Normalised access: always returns sections, synthesising a single
    /// unnamed section from flat `items` when `sections` is nil or empty.
    public var resolvedSections: [HUDSection] {
        if let sections, !sections.isEmpty { return sections }
        return [HUDSection(id: "default", title: nil, items: items)]
    }
}

public enum HUDAnchor: String, Codable, Sendable {
    case dockLeft = "dock.left"
    case dockRight = "dock.right"
}

public struct HUDRotation: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var intervalSeconds: Double

    public init(enabled: Bool = false, intervalSeconds: Double = 45) {
        self.enabled = enabled
        self.intervalSeconds = intervalSeconds
    }
}

public struct HUDItem: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var type: HUDItemType
    public var kind: String?
    public var title: String?
    public var subtitle: String?
    public var label: String?
    public var value: Double?
    public var unit: String?
    public var state: String?
    public var time: String?
    public var durationSeconds: Double?
    public var lines: [String]?

    public init(
        id: String,
        type: HUDItemType,
        kind: String? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        label: String? = nil,
        value: Double? = nil,
        unit: String? = nil,
        state: String? = nil,
        time: String? = nil,
        durationSeconds: Double? = nil,
        lines: [String]? = nil
    ) {
        self.id = id
        self.type = type
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.label = label
        self.value = value
        self.unit = unit
        self.state = state
        self.time = time
        self.durationSeconds = durationSeconds
        self.lines = lines
    }
}

public enum HUDItemType: String, Codable, Sendable {
    case text
    case metric
    case progress
    case list
    case status
    case alert
    case countdown
}

/// Lightweight payload for a single slot file (e.g. `hud_leftDock.json`).
/// Avoids the full HUDDocument envelope so writers only touch their slot.
public struct HUDSlotContent: Codable, Sendable {
    public var sections: [HUDSection]?
    public var items: [HUDItem]

    public init(sections: [HUDSection]? = nil, items: [HUDItem] = []) {
        self.sections = sections
        self.items = items
    }
}

public extension HUDDocument {
    static let empty = HUDDocument(version: 1, slots: [
        HUDSlot(id: "leftDock", anchor: .dockLeft, items: []),
        HUDSlot(id: "rightDock", anchor: .dockRight, items: [])
    ])
}
