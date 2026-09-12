import CoreGraphics
import Foundation

/// Which screen edge the Dock occupies. macOS has exactly three.
public enum DockEdge: String, Sendable, CaseIterable, Hashable {
    case left
    case right
    case bottom

    /// Axis the edge runs along.
    public var axis: Axis {
        switch self {
        case .left, .right: return .vertical
        case .bottom: return .horizontal
        }
    }

    /// Direction the tags grow in when a slot starts at the low end of the edge.
    public var naturalGrowth: GrowthDirection {
        switch self {
        case .left, .right: return .up
        case .bottom: return .right
        }
    }

    /// Slots, in fallback order.
    public var slots: [EdgeSlot] { [.primary, .secondary] }

    /// Localised name, resolved by the app layer.
    public var displayNameKey: String {
        switch self {
        case .left: return "edge.left"
        case .right: return "edge.right"
        case .bottom: return "edge.bottom"
        }
    }
}

/// An edge slot: the space below/left of the Dock (primary) or above/right of
/// it (secondary). Overflow moves from primary to secondary and never
/// compresses or overlaps.
public enum EdgeSlot: Int, Sendable, CaseIterable, Hashable {
    case primary = 0
    case secondary = 1

    public var displayNameKey: String {
        switch self {
        case .primary: return "slot.primary"
        case .secondary: return "slot.secondary"
        }
    }
}

public enum Axis: Sendable, Hashable {
    case horizontal
    case vertical
}

/// Direction a slot fills in.
public enum GrowthDirection: Sendable, Hashable {
    case up
    case down
    case left
    case right

    public var isReversed: Bool {
        switch self {
        case .up, .left: return true
        case .down, .right: return false
        }
    }

    /// The other end of the same edge.
    public var opposite: GrowthDirection {
        switch self {
        case .up: return .down
        case .down: return .up
        case .left: return .right
        case .right: return .left
        }
    }

    /// The direction that starts at the low end of an edge axis.
    static func natural(for edge: DockEdge) -> GrowthDirection { edge.naturalGrowth }
}

/// Screen geometry in AppKit coordinates (origin bottom-left).
public struct ScreenBounds: Sendable, Equatable {
    /// Full screen frame.
    public var frame: CGRect
    /// Frame excluding the menu bar and a visible Dock.
    public var visibleFrame: CGRect

    public init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }

    /// The band along the top of the screen that stays clear of the menu bar.
    public var menuBarInset: CGFloat { max(0, frame.maxY - visibleFrame.maxY) }

    /// True when the Menu Bar is permanently hidden (full screen or the
    /// "Automatically hide" setting), in which case the top of the screen is
    /// usable.
    public var hasMenuBar: Bool { menuBarInset > 1 }
}

/// Where the Dock is, how thick it is, and how far it extends along the edge.
///
/// `occupiedStart`/`occupiedEnd` are coordinates on the edge axis (x for a
/// bottom Dock, y for a side Dock). They describe the *reserved* Dock area and
/// stay valid while the Dock is auto-hidden, so a hidden Dock is never treated
/// as free space.
public struct DockBounds: Sendable, Equatable {
    public var edge: DockEdge
    /// Perpendicular extent of the Dock, measured from the screen edge.
    public var thickness: CGFloat
    public var occupiedStart: CGFloat
    public var occupiedEnd: CGFloat
    /// Whether the Dock is currently on screen (auto-hide state).
    public var isVisible: Bool
    /// Whether a Dock was found on this screen at all.
    public var isPresent: Bool
    /// Where the numbers came from — surfaced in Settings and diagnostics.
    public var source: Source

    public enum Source: String, Sendable {
        /// Measured from `NSScreen.visibleFrame` (exact reserved band).
        case reservedBand
        /// Derived from `com.apple.dock` preferences.
        case preferences
        /// A Dock-owned window from `CGWindowListCopyWindowInfo`.
        case windowList
        /// Reused from the last successful detection.
        case cache
        /// Nothing could be determined.
        case fallback

        public var displayNameKey: String {
            switch self {
            case .reservedBand: return "dock.source.reservedBand"
            case .preferences: return "dock.source.preferences"
            case .windowList: return "dock.source.windowList"
            case .cache: return "dock.source.cache"
            case .fallback: return "dock.source.fallback"
            }
        }
    }

    public init(
        edge: DockEdge,
        thickness: CGFloat,
        occupiedStart: CGFloat,
        occupiedEnd: CGFloat,
        isVisible: Bool = true,
        isPresent: Bool = true,
        source: Source = .fallback
    ) {
        self.edge = edge
        self.thickness = thickness
        self.occupiedStart = min(occupiedStart, occupiedEnd)
        self.occupiedEnd = max(occupiedStart, occupiedEnd)
        self.isVisible = isVisible
        self.isPresent = isPresent
        self.source = source
    }

    public var occupiedLength: CGFloat { max(0, occupiedEnd - occupiedStart) }

    /// A Dock that is not on this screen at all: the whole edge is free.
    public static func absent(edge: DockEdge) -> DockBounds {
        DockBounds(
            edge: edge,
            thickness: 0,
            occupiedStart: 0,
            occupiedEnd: 0,
            isVisible: false,
            isPresent: false,
            source: .fallback
        )
    }
}
