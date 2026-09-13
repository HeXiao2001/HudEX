import AppKit
import CoreGraphics
import HudEXCore

/// Everything HudEX knows about the Dock, with a cache in front of the
/// expensive parts.
///
/// Detection strategy, cheapest first:
/// 1. `com.apple.dock` preferences — orientation, auto-hide, tile size,
///    pinning and the pinned tile list. Public, permission-free, always works.
/// 2. `NSScreen.visibleFrame` — the exact reserved band while the Dock is not
///    auto-hidden.
/// 3. The user's manual calibration, when the two above are not enough.
///
/// Nothing here needs a permission. Listing other applications' windows would
/// (Screen Recording), and the Dock's Accessibility element would (Accessibility)
/// — so HudEX does neither: it reads public preferences and the screen's own
/// reserved area, and lets the person correct it in Settings if macOS reports
/// something unusual. Whatever happens, the last good geometry is kept, so a
/// failed reading never moves the bookmarks on top of the Dock.
@MainActor
final class DockGeometryProvider {
    struct Snapshot {
        var bounds: DockBounds
        var preferences: DockPreferences
        var reservedBand: CGFloat
        var screenFrame: CGRect
    }

    /// How often the expensive probes may run, at most.

    private var lastKnownGood: [String: DockBounds] = [:]
    private var cachedPreferences: DockPreferences?
    private var preferencesReadAt: Date?

    /// Set by the controller so Settings can show what happened.
    private(set) var lastDiagnostic: String?

    // MARK: - Snapshot

    /// Current best knowledge of the Dock for one screen.
    ///
    /// - Parameter allowExpensiveProbes: pass `true` only for real events; it
    ///   forces a fresh read of the Dock's preferences (never a window scan —
    ///   listing other apps' windows needs Screen Recording, and HudEX asks for
    ///   no permissions at all).
    ///   (launch, screen change, space change, wake, Dock preference change).
    func snapshot(for screen: NSScreen, allowExpensiveProbes: Bool = false) -> Snapshot {
        let preferences = readPreferences(force: allowExpensiveProbes)
        let bounds = computeBounds(for: screen, preferences: preferences, allowExpensiveProbes: allowExpensiveProbes)
        return Snapshot(
            bounds: bounds,
            preferences: preferences,
            reservedBand: ScreenGeometry.reservedDockBand(on: screen, edge: bounds.edge),
            screenFrame: screen.frame
        )
    }

    func resetCache() {
        lastKnownGood.removeAll()
        cachedPreferences = nil
        preferencesReadAt = nil
        lastDiagnostic = nil
    }

    func invalidatePreferences() {
        cachedPreferences = nil
        preferencesReadAt = nil
    }

    // MARK: - Dock preferences

    func readPreferences(force: Bool) -> DockPreferences {
        if !force, let cachedPreferences, let preferencesReadAt, Date().timeIntervalSince(preferencesReadAt) < 5 {
            return cachedPreferences
        }
        let preferences = Self.loadPreferencesFromSystem()
        cachedPreferences = preferences
        preferencesReadAt = Date()
        return preferences
    }

    /// Reads the Dock's own preferences. `UserDefaults(suiteName:)` keeps a
    /// per-process cache, so this does not hit the disk on every call.
    static func loadPreferencesFromSystem() -> DockPreferences {
        guard let defaults = UserDefaults(suiteName: "com.apple.dock") else {
            return .fallback
        }
        let tileSize = defaults.object(forKey: "tilesize") as? Double
        let largerSize = defaults.object(forKey: "largesize") as? Double
        return DockPreferences(
            orientation: DockPreferences.parseOrientation(defaults.string(forKey: "orientation")),
            autoHide: defaults.object(forKey: "autohide") as? Bool ?? false,
            tileSize: CGFloat(tileSize ?? DockPreferences.fallback.tileSize),
            magnification: defaults.object(forKey: "magnification") as? Bool ?? false,
            largeSize: CGFloat(largerSize ?? DockPreferences.fallback.largeSize),
            pinning: DockPreferences.parsePinning(defaults.object(forKey: "pinning")),
            persistentAppCount: defaults.array(forKey: "persistent-apps")?.count ?? 0,
            persistentOtherCount: defaults.array(forKey: "persistent-others")?.count ?? 0
        )
    }

    // MARK: - Bounds

    private func computeBounds(
        for screen: NSScreen,
        preferences: DockPreferences,
        allowExpensiveProbes: Bool
    ) -> DockBounds {
        let displayID = ScreenGeometry.displayID(of: screen)
        let settings = Preferences.shared

        // 1. Edge: Dock preference first, then the reserved bands.
        let edge = preferences.orientation
            ?? ScreenGeometry.edgeFromReservedBands(on: screen)
            ?? lastKnownGood[displayID]?.edge
            ?? .bottom

        let reservedBand = ScreenGeometry.reservedDockBand(on: screen, edge: edge)
        let dockOnThisScreen = preferences.orientation != nil
            ? (reservedBand > 1 || preferences.autoHide || lastKnownGood[displayID] != nil)
            : reservedBand > 1

        guard dockOnThisScreen else {
            // The Dock lives on another display (or none): the whole edge is free.
            let bounds = DockBounds.absent(edge: edge)
            lastKnownGood[displayID] = bounds
            return bounds
        }

        var bounds = DockGeometryEstimator.bounds(
            edge: edge,
            preferences: preferences,
            screen: ScreenGeometry.bounds(of: screen),
            reservedBand: reservedBand,
            isVisible: true,
            isPresent: true,
            manualThickness: settings.dockThicknessOverride > 0 ? CGFloat(settings.dockThicknessOverride) : nil,
            manualLength: settings.dockLengthOverride > 0 ? CGFloat(settings.dockLengthOverride) : nil
        )

        lastDiagnostic = L10n.t(bounds.source.displayNameKey)

        // Never let a detection failure shrink the reserved area: keep the
        // larger (safer) of the new and the last good value.
        if let previous = lastKnownGood[displayID], previous.isPresent, bounds.isPresent {
            let keepStart = min(previous.occupiedStart, bounds.occupiedStart)
            let keepEnd = max(previous.occupiedEnd, bounds.occupiedEnd)
            if keepStart != bounds.occupiedStart || keepEnd != bounds.occupiedEnd {
                bounds = DockBounds(
                    edge: bounds.edge,
                    thickness: max(previous.thickness, bounds.thickness),
                    occupiedStart: keepStart,
                    occupiedEnd: keepEnd,
                    isVisible: bounds.isVisible,
                    isPresent: true,
                    source: .cache
                )
            }
        }

        lastKnownGood[displayID] = bounds
        return bounds
    }


    /// Looks for a Dock-owned window that is a thin band against the screen
    /// edge. Returns `nil` on macOS versions where the Dock window covers the
    /// whole screen (macOS 26), which is why it is only a refinement.
}
