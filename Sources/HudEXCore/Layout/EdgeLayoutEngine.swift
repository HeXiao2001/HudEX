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

    /// Slots, in fallback order.
    public var slots: [EdgeSlot] { [.primary, .secondary] }

    public var displayName: String {
        switch self {
        case .left: return "左侧"
        case .right: return "右侧"
        case .bottom: return "下方"
        }
    }
}

/// An edge slot: the space below/left of the Dock (primary) or above/right of
/// it (secondary). Overflow moves from primary to secondary and never
/// compresses or overlaps.
public enum EdgeSlot: Int, Sendable, CaseIterable, Hashable {
    case primary = 0
    case secondary = 1

    public var displayName: String {
        switch self {
        case .primary: return "主位置"
        case .secondary: return "溢出位置"
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

    public init(edge: DockEdge, slot: EdgeSlot) {
        switch (edge, slot) {
        case (.left, .primary), (.right, .primary): self = .up
        case (.left, .secondary), (.right, .secondary): self = .down
        case (.bottom, .primary): self = .right
        case (.bottom, .secondary): self = .left
        }
    }

    public var isReversed: Bool {
        switch self {
        case .up, .left: return true
        case .down, .right: return false
        }
    }
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
        /// The Dock's own Accessibility element (only when already trusted).
        case accessibility
        /// Reused from the last successful detection.
        case cache
        /// Nothing could be determined.
        case fallback

        public var displayName: String {
            switch self {
            case .reservedBand: return "屏幕保留区（精确）"
            case .preferences: return "Dock 偏好设置（估算）"
            case .windowList: return "CGWindowList（精确）"
            case .accessibility: return "辅助功能 API（精确，已授权）"
            case .cache: return "上次成功检测"
            case .fallback: return "默认值"
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

/// The size of one edge tab.
///
/// A tab is a bookmark that sits in the Dock's own band: it may never be
/// thicker than the Dock, and it stays short along the edge so it reads as a
/// bookmark next to a Dock icon rather than as a second sidebar.
public struct TabMetrics: Sendable, Equatable {
    /// Perpendicular extent (width for a side Dock, height for a bottom Dock).
    public var thickness: CGFloat
    /// Extent along the edge.
    public var length: CGFloat
    /// Gap between two tabs.
    public var spacing: CGFloat
    /// Inset from the screen corner.
    public var cornerInset: CGFloat
    /// Gap kept between the last tab and the Dock.
    public var dockGap: CGFloat
    /// Point size of the tab label.
    public var fontSize: CGFloat

    public static let minimumFontSize: CGFloat = 9
    public static let maximumFontSize: CGFloat = 12
    public static let maximumThickness: CGFloat = 56
    public static let minimumThickness: CGFloat = 22

    public init(
        thickness: CGFloat,
        length: CGFloat,
        spacing: CGFloat = 5,
        cornerInset: CGFloat = 8,
        dockGap: CGFloat = 12,
        fontSize: CGFloat = 11
    ) {
        self.thickness = thickness
        self.length = length
        self.spacing = spacing
        self.cornerInset = cornerInset
        self.dockGap = dockGap
        self.fontSize = fontSize
    }

    /// Derives tab metrics from the live Dock thickness.
    ///
    /// - Parameter fontSizeOverride: user preference; `nil` keeps the
    ///   Dock-derived size. The result is always clamped to 9–12 pt.
    public static func make(
        dockThickness: CGFloat,
        fontSizeOverride: CGFloat? = nil,
        protrusionOverride: CGFloat? = nil,
        lengthOverride: CGFloat? = nil,
        edgeGap: CGFloat = 12,
        cornerInset: CGFloat = 8
    ) -> TabMetrics {
        let reference = dockThickness > 0 ? dockThickness : 44
        let rawFontSize = fontSizeOverride ?? (reference * 0.30)
        let fontSize = min(max(rawFontSize, minimumFontSize), maximumFontSize)
        let rawThickness = protrusionOverride ?? reference
        let thickness = min(max(rawThickness, minimumThickness), maximumThickness)
        let length = lengthOverride ?? (fontSize * 1.15 + 11).rounded()
        return TabMetrics(
            thickness: thickness,
            length: length,
            spacing: 5,
            cornerInset: cornerInset,
            dockGap: edgeGap,
            fontSize: fontSize
        )
    }
}

/// One placed tab.
public struct TagPlacement: Sendable, Equatable {
    /// Index into the project list.
    public var index: Int
    public var slot: EdgeSlot
    /// Frame in screen coordinates.
    public var frame: CGRect
}

/// Everything the window layer needs in order to draw the tabs.
public struct EdgeLayoutPlan: Sendable, Equatable {
    public var edge: DockEdge
    public var metrics: TabMetrics
    public var placements: [TagPlacement]
    /// Projects that did not fit even in the secondary slot.
    public var overflowCount: Int
    /// The free ranges each slot drew from, for diagnostics and Settings.
    public var slotRanges: [EdgeSlot: ClosedRange<CGFloat>]
    /// Union of all placements, used to size the container panel.
    public var boundingBox: CGRect

    public static let empty = EdgeLayoutPlan(
        edge: .bottom,
        metrics: TabMetrics.make(dockThickness: 44),
        placements: [],
        overflowCount: 0,
        slotRanges: [:],
        boundingBox: .zero
    )

    public func placement(forProjectAt index: Int) -> TagPlacement? {
        placements.first { $0.index == index }
    }
}

/// Places tabs in the edge space the Dock does not occupy.
///
/// One engine, three edges: the slot ranges are computed from the Dock bounds
/// and the growth direction follows the edge, so there is no per-edge copy of
/// the layout logic.
public enum EdgeLayoutEngine {
    public static func plan(
        projectCount: Int,
        metrics: TabMetrics,
        screen: ScreenBounds,
        dock: DockBounds,
        limits: TagLimits = .unlimited
    ) -> EdgeLayoutPlan {
        guard projectCount > 0 else {
            return EdgeLayoutPlan(
                edge: dock.edge,
                metrics: metrics,
                placements: [],
                overflowCount: 0,
                slotRanges: [:],
                boundingBox: .zero
            )
        }

        let ranges = slotRanges(metrics: metrics, screen: screen, dock: dock)
        let visibleCount = limits.visibleCount(for: projectCount)
        var placements: [TagPlacement] = []
        var index = 0

        for slot in dock.edge.slots {
            guard index < visibleCount, let range = ranges[slot] else { continue }
            let capacity = limits.slotCapacity(for: capacity(in: range, metrics: metrics))
            for offset in 0..<capacity where index < visibleCount {
                placements.append(
                    TagPlacement(
                        index: index,
                        slot: slot,
                        frame: frame(
                            forOffset: offset,
                            in: range,
                            slot: slot,
                            metrics: metrics,
                            screen: screen,
                            edge: dock.edge
                        )
                    )
                )
                index += 1
            }
        }
        let overflow = max(0, projectCount - index)

        let boundingBox = placements.reduce(CGRect.null) { $0.union($1.frame) }
        return EdgeLayoutPlan(
            edge: dock.edge,
            metrics: metrics,
            placements: placements,
            overflowCount: overflow,
            slotRanges: ranges,
            boundingBox: boundingBox.isNull ? .zero : boundingBox
        )
    }

    /// Free ranges for the two slots, in screen coordinates along the edge axis.
    public static func slotRanges(
        metrics: TabMetrics,
        screen: ScreenBounds,
        dock: DockBounds
    ) -> [EdgeSlot: ClosedRange<CGFloat>] {
        switch dock.edge {
        case .left, .right:
            // Do not cover the menu bar at the top.
            let usableTop = screen.hasMenuBar
                ? screen.visibleFrame.maxY
                : screen.frame.maxY
            let bottom = screen.frame.minY
            let top = max(bottom, usableTop)

            guard dock.isPresent else {
                let middle = (bottom + top) / 2
                let primary = (bottom + metrics.cornerInset)...max(bottom + metrics.cornerInset, middle - metrics.dockGap)
                let secondary = min(top - metrics.cornerInset, middle + metrics.dockGap)...(top - metrics.cornerInset)
                return [.primary: primary, .secondary: secondary]
            }

            let primaryLower = bottom + metrics.cornerInset
            let primaryUpper = dock.occupiedStart - metrics.dockGap
            let secondaryLower = dock.occupiedEnd + metrics.dockGap
            let secondaryUpper = top - metrics.cornerInset

            var ranges: [EdgeSlot: ClosedRange<CGFloat>] = [:]
            if primaryUpper > primaryLower {
                ranges[.primary] = primaryLower...primaryUpper
            }
            if secondaryUpper > secondaryLower {
                ranges[.secondary] = secondaryLower...secondaryUpper
            }
            return ranges

        case .bottom:
            let left = screen.frame.minX
            let right = screen.frame.maxX

            guard dock.isPresent else {
                let middle = (left + right) / 2
                let primary = (left + metrics.cornerInset)...max(left + metrics.cornerInset, middle - metrics.dockGap)
                let secondary = min(right - metrics.cornerInset, middle + metrics.dockGap)...(right - metrics.cornerInset)
                return [.primary: primary, .secondary: secondary]
            }

            let primaryLower = left + metrics.cornerInset
            let primaryUpper = dock.occupiedStart - metrics.dockGap
            let secondaryLower = dock.occupiedEnd + metrics.dockGap
            let secondaryUpper = right - metrics.cornerInset

            var ranges: [EdgeSlot: ClosedRange<CGFloat>] = [:]
            if primaryUpper > primaryLower {
                ranges[.primary] = primaryLower...primaryUpper
            }
            if secondaryUpper > secondaryLower {
                ranges[.secondary] = secondaryLower...secondaryUpper
            }
            return ranges
        }
    }

    /// How many tabs fit in a range without shrinking or overlapping.
    public static func capacity(in range: ClosedRange<CGFloat>, metrics: TabMetrics) -> Int {
        let available = range.upperBound - range.lowerBound
        guard available >= metrics.length else { return 0 }
        let step = metrics.length + metrics.spacing
        return max(1, Int(floor((available + metrics.spacing) / step)))
    }

    private static func frame(
        forOffset offset: Int,
        in range: ClosedRange<CGFloat>,
        slot: EdgeSlot,
        metrics: TabMetrics,
        screen: ScreenBounds,
        edge: DockEdge
    ) -> CGRect {
        let step = metrics.length + metrics.spacing
        let direction = GrowthDirection(edge: edge, slot: slot)
        let start: CGFloat
        switch direction {
        case .up, .right:
            start = range.lowerBound + CGFloat(offset) * step
        case .down, .left:
            start = range.upperBound - metrics.length - CGFloat(offset) * step
        }

        let frame = screen.frame
        switch edge {
        case .left:
            return CGRect(x: frame.minX, y: start, width: metrics.thickness, height: metrics.length)
        case .right:
            return CGRect(x: frame.maxX - metrics.thickness, y: start, width: metrics.thickness, height: metrics.length)
        case .bottom:
            return CGRect(x: start, y: frame.minY, width: metrics.length, height: metrics.thickness)
        }
    }
}

/// Caps on how many tags are drawn at all, and how many share one slot.
///
/// A user who wants "at most five bookmarks, three per side" should not have to
/// make the tags smaller: the extras are simply not drawn.
public struct TagLimits: Sendable, Equatable {
    /// Highest number of tags shown in total. `0` means no limit.
    public var maxTags: Int
    /// Highest number of tags in a single slot before the other slot is used.
    /// `0` means no limit.
    public var maxTagsPerSlot: Int

    public init(maxTags: Int = 0, maxTagsPerSlot: Int = 0) {
        self.maxTags = max(0, maxTags)
        self.maxTagsPerSlot = max(0, maxTagsPerSlot)
    }

    public static let unlimited = TagLimits()

    func visibleCount(for projectCount: Int) -> Int {
        maxTags > 0 ? min(projectCount, maxTags) : projectCount
    }

    func slotCapacity(for capacity: Int) -> Int {
        maxTagsPerSlot > 0 ? min(capacity, maxTagsPerSlot) : capacity
    }
}
