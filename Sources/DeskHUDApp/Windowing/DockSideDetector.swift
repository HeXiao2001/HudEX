import AppKit

/// Which screen edge hosts the Dock, inferred from the band `visibleFrame`
/// reserves. Shared by the window manager (panel placement) and the Settings
/// layout preview. Auto-hidden Docks are not detectable this way.
enum DockSide {
    case bottom
    case left
    case right
    case none

    var isVertical: Bool { self == .left || self == .right }

    static func detect(on screen: NSScreen) -> DockSide {
        let sf = screen.frame
        let vf = screen.visibleFrame
        if vf.minY - sf.minY > 24 { return .bottom }
        if vf.minX - sf.minX > 24 { return .left }
        if sf.maxX - vf.maxX > 24 { return .right }
        return .none
    }
}
