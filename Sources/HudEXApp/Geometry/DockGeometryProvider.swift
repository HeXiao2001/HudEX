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
/// 3. `CGWindowListCopyWindowInfo`, paused to Dock-owned windows that form a
///    thin band against a screen edge. This is the documented approach, but on
///    macOS 26 the Dock's own window covers the whole screen, so it usually
///    yields nothing; it is therefore only called on real events and never in a
///    loop. (Apple documents the call as relatively expensive.)
/// 4. The Dock's Accessibility element, *only* when HudEX is already trusted —
///    HudEX never prompts for that permission. It gives exact bounds for users
///    who happen to have granted it.
///
/// Whatever happens, the last good geometry is kept: a failed probe never moves
/// the tabs on top of the Dock.
@MainActor
final class DockGeometryProvider {
    struct Snapshot {
        var bounds: DockBounds
        var preferences: DockPreferences
        var reservedBand: CGFloat
        var screenFrame: CGRect
    }

    /// How often the expensive probes may run, at most.
    private let deepScanMinimumInterval: TimeInterval = 30

    private var lastKnownGood: [String: DockBounds] = [:]
    private var lastDeepScan: [String: Date] = [:]
    private var cachedPreferences: DockPreferences?
    private var preferencesReadAt: Date?

    /// Set by the controller so Settings can show what happened.
    private(set) var lastDiagnostic: String?

    // MARK: - Snapshot

    /// Current best knowledge of the Dock for one screen.
    ///
    /// - Parameter allowExpensiveProbes: pass `true` only for real events
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
        lastDeepScan.removeAll()
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

        if allowExpensiveProbes, settings.dockLengthOverride <= 0 {
            if let measured = measuredBounds(for: screen, edge: edge), measured.occupiedLength > 0 {
                bounds = measured
                lastDiagnostic = L10n.t(measured.source.displayNameKey)
            } else {
                lastDiagnostic = L10n.t(bounds.source.displayNameKey)
            }
        }

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

    // MARK: - CGWindowList probe

    /// Looks for a Dock-owned window that is a thin band against the screen
    /// edge. Returns `nil` on macOS versions where the Dock window covers the
    /// whole screen (macOS 26), which is why it is only a refinement.
    private func measuredBounds(for screen: NSScreen, edge: DockEdge) -> DockBounds? {
        let displayID = ScreenGeometry.displayID(of: screen)
        let now = Date()
        if let last = lastDeepScan[displayID], now.timeIntervalSince(last) < deepScanMinimumInterval {
            return nil
        }
        lastDeepScan[displayID] = now

        guard let dockPID = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?
            .processIdentifier else {
            return nil
        }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let mainHeight = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let screenFrame = screen.frame

        for window in windows {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid == dockPID else { continue }
            guard let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }

            let appKitRect = ScreenCoordinates.appKitRect(
                fromWindowServerRect: rect,
                mainScreenHeight: mainHeight
            )
            guard appKitRect.intersects(screenFrame) else { continue }

            // A Dock strip is thin on exactly one axis and hugs one edge; the
            // full-screen Dock window macOS 26 uses is rejected here.
            switch edge {
            case .left, .right:
                let thickness = appKitRect.width
                guard thickness > 10, thickness < screenFrame.height * 0.5 else { continue }
                guard abs(appKitRect.height - screenFrame.height) > 40 else { continue }
            case .bottom:
                let thickness = appKitRect.height
                guard thickness > 10, thickness < screenFrame.width * 0.5 else { continue }
                guard abs(appKitRect.width - screenFrame.width) > 40 else { continue }
            }

            let clamped = appKitRect.intersection(screenFrame)
            switch edge {
            case .left, .right:
                return DockBounds(
                    edge: edge,
                    thickness: clamped.width,
                    occupiedStart: clamped.minY,
                    occupiedEnd: clamped.maxY,
                    isVisible: true,
                    isPresent: true,
                    source: .windowList
                )
            case .bottom:
                return DockBounds(
                    edge: edge,
                    thickness: clamped.height,
                    occupiedStart: clamped.minX,
                    occupiedEnd: clamped.maxX,
                    isVisible: true,
                    isPresent: true,
                    source: .windowList
                )
            }
        }

        Log.debug(Log.dock, "CGWindowList: no thin Dock window for edge \(edge.rawValue)")
        return nil
    }

}
