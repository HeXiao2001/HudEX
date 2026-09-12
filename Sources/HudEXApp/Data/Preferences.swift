import Foundation
import HudEXCore

/// User preferences, backed by `UserDefaults`.
///
/// Kept deliberately small: HudEX is configured by editing `HudEX.md` and by a
/// handful of switches, not by a wall of parameters.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Key {
        static let sourcePath = "source.path"
        static let showTags = "layout.showTags"
        static let showMenuBarIcon = "menuBar.showIcon"
        static let fontSize = "appearance.fontSize"
        static let edgeGap = "layout.edgeGap"
        static let cornerInset = "layout.cornerInset"
        static let showUpdatedTime = "appearance.showUpdatedTime"
        static let dockThicknessOverride = "layout.dockThicknessOverride"
        static let dockLengthOverride = "layout.dockLengthOverride"
        static let tabProtrusion = "layout.tabProtrusion"
        static let tabLength = "layout.tabLength"
        static let maxTags = "layout.maxTags"
        static let maxTagsPerSlot = "layout.maxTagsPerSlot"
        static let layoutKind = "layout.kind"
        static let layoutEdge = "layout.fixedEdge"
        static let layoutAnchor = "layout.fixedAnchor"
        static let layoutOffset = "layout.fixedOffset"
        static let stackEnabled = "stack.enabled"
        static let stackOverlap = "stack.overlap"
        static let stackRotation = "stack.rotation"
        static let stackStagger = "stack.stagger"
        static let settingsWriteBack = "settings.writeBack"
        static let language = "ui.language"
        static let thresholdActive = "appearance.threshold.active"
        static let thresholdAttention = "appearance.threshold.attention"
        static let thresholdAging = "appearance.threshold.aging"
    }

    private let defaults: UserDefaults

    // MARK: - Source

    /// Path of `HudEX.md`. Empty means "resolve automatically".
    @Published var sourcePath: String {
        didSet { defaults.set(sourcePath, forKey: Key.sourcePath) }
    }

    // MARK: - Visibility

    @Published var showTags: Bool {
        didSet { defaults.set(showTags, forKey: Key.showTags) }
    }

    /// Drives `MenuBarExtra(isInserted:)`.
    @Published var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) }
    }

    // MARK: - Layout

    /// Gap kept between the tabs and the Dock.
    @Published var edgeGap: Double {
        didSet { defaults.set(edgeGap, forKey: Key.edgeGap) }
    }

    /// Gap kept between the tabs and the screen corner.
    @Published var cornerInset: Double {
        didSet { defaults.set(cornerInset, forKey: Key.cornerInset) }
    }

    /// Manual Dock thickness calibration; 0 = automatic.
    @Published var dockThicknessOverride: Double {
        didSet { defaults.set(dockThicknessOverride, forKey: Key.dockThicknessOverride) }
    }

    /// Manual Dock length calibration; 0 = automatic.
    @Published var dockLengthOverride: Double {
        didSet { defaults.set(dockLengthOverride, forKey: Key.dockLengthOverride) }
    }

    /// How far a tag reaches into the screen. 0 = follow the Dock thickness.
    @Published var tabProtrusion: Double {
        didSet { defaults.set(tabProtrusion, forKey: Key.tabProtrusion) }
    }

    /// How long a tag is along the screen edge. 0 = derived from the font size.
    @Published var tabLength: Double {
        didSet { defaults.set(tabLength, forKey: Key.tabLength) }
    }

    /// Which placement mode the user picked.
    @Published var layoutKind: LayoutMode.Kind {
        didSet { defaults.set(layoutKind.rawValue, forKey: Key.layoutKind) }
    }

    /// Screen edge used by `.fixedEdge`.
    @Published var layoutEdge: DockEdge {
        didSet { defaults.set(layoutEdge.rawValue, forKey: Key.layoutEdge) }
    }

    /// Anchor along that edge.
    @Published var layoutAnchor: LayoutMode.Anchor {
        didSet { defaults.set(layoutAnchor.rawValue, forKey: Key.layoutAnchor) }
    }

    /// Extra offset along the edge.
    @Published var layoutOffset: Double {
        didSet { defaults.set(layoutOffset, forKey: Key.layoutOffset) }
    }

    /// Overlapping "stack of bookmarks" look.
    @Published var stackEnabled: Bool {
        didSet { defaults.set(stackEnabled, forKey: Key.stackEnabled) }
    }

    @Published var stackOverlap: Double {
        didSet { defaults.set(stackOverlap, forKey: Key.stackOverlap) }
    }

    @Published var stackRotation: Double {
        didSet { defaults.set(stackRotation, forKey: Key.stackRotation) }
    }

    @Published var stackStagger: Double {
        didSet { defaults.set(stackStagger, forKey: Key.stackStagger) }
    }

    /// UI language: "" follows the system, otherwise `en` / `zh-Hans`.
    @Published var language: String {
        didSet {
            defaults.set(language, forKey: Key.language)
            L10n.setLanguageOverride(language.isEmpty ? nil : language)
        }
    }

    /// Write settings back into the Markdown file.
    @Published var settingsWriteBack: Bool {
        didSet { defaults.set(settingsWriteBack, forKey: Key.settingsWriteBack) }
    }

    /// Highest number of tags shown at all. 0 = no limit.
    @Published var maxTags: Int {
        didSet { defaults.set(maxTags, forKey: Key.maxTags) }
    }

    /// Highest number of tags in one slot before the other slot is used.
    /// 0 = no limit.
    @Published var maxTagsPerSlot: Int {
        didSet { defaults.set(maxTagsPerSlot, forKey: Key.maxTagsPerSlot) }
    }

    // MARK: - Appearance

    /// Tag label size; 0 = derived from the Dock thickness.
    @Published var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: Key.fontSize) }
    }

    /// Show `更新：` inside the hover preview header line.
    @Published var showUpdatedTime: Bool {
        didSet { defaults.set(showUpdatedTime, forKey: Key.showUpdatedTime) }
    }

    @Published var thresholdActive: Int {
        didSet { defaults.set(thresholdActive, forKey: Key.thresholdActive) }
    }

    @Published var thresholdAttention: Int {
        didSet { defaults.set(thresholdAttention, forKey: Key.thresholdAttention) }
    }

    @Published var thresholdAging: Int {
        didSet { defaults.set(thresholdAging, forKey: Key.thresholdAging) }
    }

    // MARK: - Derived

    /// Resolved source URL: the user's choice, else the first candidate that
    /// exists, else the default location.
    var resolvedSourceURL: URL {
        if !sourcePath.isEmpty {
            return SourceLocator.url(forStoredPath: sourcePath)
        }
        let candidates = SourceLocator.candidates()
        if let existing = SourceLocator.firstExisting(candidates: candidates) {
            return existing
        }
        return candidates[0]
    }

    var colorThresholds: TagColorThresholds {
        TagColorThresholds(
            activeThroughDays: thresholdActive,
            attentionThroughDays: thresholdAttention,
            agingThroughDays: thresholdAging
        )
    }

    var fontSizeOverride: CGFloat? {
        fontSize > 0 ? CGFloat(fontSize) : nil
    }

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sourcePath = defaults.string(forKey: Key.sourcePath) ?? ""
        showTags = defaults.object(forKey: Key.showTags) as? Bool ?? true
        showMenuBarIcon = defaults.object(forKey: Key.showMenuBarIcon) as? Bool ?? true
        edgeGap = defaults.object(forKey: Key.edgeGap) as? Double ?? 12
        cornerInset = defaults.object(forKey: Key.cornerInset) as? Double ?? 8
        dockThicknessOverride = defaults.object(forKey: Key.dockThicknessOverride) as? Double ?? 0
        dockLengthOverride = defaults.object(forKey: Key.dockLengthOverride) as? Double ?? 0
        tabProtrusion = defaults.object(forKey: Key.tabProtrusion) as? Double ?? 0
        tabLength = defaults.object(forKey: Key.tabLength) as? Double ?? 0
        maxTags = defaults.object(forKey: Key.maxTags) as? Int ?? 0
        maxTagsPerSlot = defaults.object(forKey: Key.maxTagsPerSlot) as? Int ?? 0
        layoutKind = LayoutMode.Kind(rawValue: defaults.string(forKey: Key.layoutKind) ?? "") ?? .dockAdaptive
        layoutEdge = DockEdge(rawValue: defaults.string(forKey: Key.layoutEdge) ?? "") ?? .bottom
        layoutAnchor = LayoutMode.Anchor(rawValue: defaults.string(forKey: Key.layoutAnchor) ?? "") ?? .start
        layoutOffset = defaults.object(forKey: Key.layoutOffset) as? Double ?? 0
        stackEnabled = defaults.object(forKey: Key.stackEnabled) as? Bool ?? true
        stackOverlap = defaults.object(forKey: Key.stackOverlap) as? Double ?? 0.34
        stackRotation = defaults.object(forKey: Key.stackRotation) as? Double ?? -5
        stackStagger = defaults.object(forKey: Key.stackStagger) as? Double ?? 2.5
        settingsWriteBack = defaults.object(forKey: Key.settingsWriteBack) as? Bool ?? true
        let storedLanguage = defaults.string(forKey: Key.language) ?? ""
        language = storedLanguage
        // `didSet` does not run during init, so the override is applied here.
        L10n.setLanguageOverride(storedLanguage.isEmpty ? nil : storedLanguage)
        fontSize = defaults.object(forKey: Key.fontSize) as? Double ?? 0
        showUpdatedTime = defaults.object(forKey: Key.showUpdatedTime) as? Bool ?? true
        thresholdActive = defaults.object(forKey: Key.thresholdActive) as? Int ?? 2
        thresholdAttention = defaults.object(forKey: Key.thresholdAttention) as? Int ?? 6
        thresholdAging = defaults.object(forKey: Key.thresholdAging) as? Int ?? 14
    }

    // MARK: - Mutation helpers used by Settings

    func setSourceURL(_ url: URL) {
        sourcePath = url.path
    }

    func resetDockCalibration() {
        dockThicknessOverride = 0
        dockLengthOverride = 0
    }

    func resetTagSize() {
        tabProtrusion = 0
        tabLength = 0
        fontSize = 0
    }

    var tagProtrusionOverride: CGFloat? { tabProtrusion > 0 ? CGFloat(tabProtrusion) : nil }
    var tabLengthOverride: CGFloat? { tabLength > 0 ? CGFloat(tabLength) : nil }

    var tagLimits: TagLimits {
        TagLimits(maxTags: maxTags, maxTagsPerSlot: maxTagsPerSlot)
    }

    var layoutMode: LayoutMode {
        LayoutMode(
            kind: layoutKind,
            edge: layoutEdge,
            anchor: layoutAnchor,
            offset: CGFloat(layoutOffset)
        )
    }

    var stackStyle: StackStyle {
        StackStyle(
            isEnabled: stackEnabled,
            overlapFraction: CGFloat(stackOverlap),
            rotationDegrees: CGFloat(stackRotation),
            stagger: CGFloat(stackStagger)
        )
    }
}
