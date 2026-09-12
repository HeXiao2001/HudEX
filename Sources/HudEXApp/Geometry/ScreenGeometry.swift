import AppKit
import HudEXCore

/// Converts AppKit screens into the plain geometry values the layout engine
/// uses, and decides which screen HudEX draws on.
///
/// All values are logical points: nothing here multiplies by a backing scale
/// factor, so Retina, scaled and mixed-resolution setups behave identically.
enum ScreenGeometry {
    static func bounds(of screen: NSScreen) -> ScreenBounds {
        ScreenBounds(frame: screen.frame, visibleFrame: screen.visibleFrame)
    }

    /// Stable identifier for caching Dock geometry per display.
    static func displayID(of screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return "display-\(number.uint32Value)"
        }
        return "display-\(screen.localizedName)"
    }

    /// Thickness of the band the Dock reserves on this screen, measured from
    /// `visibleFrame`. Zero when the Dock reserves nothing (auto-hidden, or the
    /// Dock is on another display).
    static func reservedDockBand(on screen: NSScreen, edge: DockEdge) -> CGFloat {
        let frame = screen.frame
        let visible = screen.visibleFrame
        switch edge {
        case .bottom: return max(0, visible.minY - frame.minY)
        case .left: return max(0, visible.minX - frame.minX)
        case .right: return max(0, frame.maxX - visible.maxX)
        }
    }

    /// The edge the Dock sits on, derived from `visibleFrame` alone. Used when
    /// the Dock preferences cannot be read.
    static func edgeFromReservedBands(on screen: NSScreen) -> DockEdge? {
        let frame = screen.frame
        let visible = screen.visibleFrame
        let bottom = visible.minY - frame.minY
        let left = visible.minX - frame.minX
        let right = frame.maxX - visible.maxX
        let threshold: CGFloat = 24

        // A bottom Dock shortens the screen the most; side Docks are thinner.
        if bottom > threshold { return .bottom }
        if left > threshold { return .left }
        if right > threshold { return .right }
        return nil
    }

    /// The screen that hosts the Dock: the one whose reserved band is non-zero,
    /// otherwise the main screen. Keeps HudEX correct on multi-display setups
    /// without scattering per-screen logic through the app.
    static func dockScreen(screens: [NSScreen] = NSScreen.screens, main: NSScreen? = NSScreen.main) -> NSScreen? {
        guard !screens.isEmpty else { return nil }
        for screen in screens where edgeFromReservedBands(on: screen) != nil {
            return screen
        }
        return main ?? screens.first
    }
}

/// Converts window-server coordinates (top-left origin, spanning every display)
/// into AppKit coordinates (bottom-left origin of each screen).
enum ScreenCoordinates {
    static func appKitRect(fromWindowServerRect rect: CGRect, mainScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: mainScreenHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
