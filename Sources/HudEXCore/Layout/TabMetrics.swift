import CoreGraphics
import Foundation

// MARK: - Tab sizing

/// The size of one edge tab.
///
/// A tab is a bookmark that sits in the Dock's own band: by default it is never
/// thicker than the Dock, and it stays short along the edge so it reads as a
/// bookmark next to a Dock icon rather than as a second sidebar. Both numbers
/// can be overridden by the user (and then only absolute sanity bounds apply).
public struct TabMetrics: Sendable, Equatable {
    /// Perpendicular extent (width for a side Dock, height for a bottom Dock).
    public var thickness: CGFloat
    /// Extent along the edge.
    public var length: CGFloat
    /// Gap between two tabs when they are not stacked.
    public var spacing: CGFloat
    /// Inset from the screen corner.
    public var cornerInset: CGFloat
    /// Gap kept between the last tab and the Dock.
    public var dockGap: CGFloat
    /// Point size of the tab label.
    public var fontSize: CGFloat
    /// Stacking (overlapping bookmark) style.
    public var stack: StackStyle

    /// Absolute bounds used when the user overrides the automatic size.
    public static let minimumFontSize: CGFloat = 8
    public static let maximumFontSize: CGFloat = 24
    public static let minimumThickness: CGFloat = 12
    public static let maximumThickness: CGFloat = 240
    public static let minimumLength: CGFloat = 12
    public static let maximumLength: CGFloat = 240

    public init(
        thickness: CGFloat,
        length: CGFloat,
        spacing: CGFloat = 5,
        cornerInset: CGFloat = 8,
        dockGap: CGFloat = 12,
        fontSize: CGFloat = 11,
        stack: StackStyle = .plain
    ) {
        self.thickness = thickness
        self.length = length
        self.spacing = spacing
        self.cornerInset = cornerInset
        self.dockGap = dockGap
        self.fontSize = fontSize
        self.stack = stack
    }

    /// Derives tab metrics from the live Dock thickness.
    ///
    /// - Parameters:
    ///   - fontSizeOverride: user preference; `nil` keeps the Dock-derived size.
    ///   - protrusionOverride: tag width/height; `nil` follows the Dock.
    ///   - lengthOverride: tag length along the edge; `nil` follows the font.
    public static func make(
        dockThickness: CGFloat,
        fontSizeOverride: CGFloat? = nil,
        protrusionOverride: CGFloat? = nil,
        lengthOverride: CGFloat? = nil,
        edgeGap: CGFloat = 12,
        cornerInset: CGFloat = 8,
        stack: StackStyle = .plain
    ) -> TabMetrics {
        let reference = dockThickness > 0 ? dockThickness : 44
        let rawFontSize = fontSizeOverride ?? (reference * 0.30)
        let fontSize = min(max(rawFontSize, minimumFontSize), maximumFontSize)
        let rawThickness = protrusionOverride ?? reference
        let thickness = min(max(rawThickness, minimumThickness), maximumThickness)
        let rawLength = lengthOverride ?? (fontSize * 1.15 + 11).rounded()
        let length = min(max(rawLength, minimumLength), maximumLength)
        return TabMetrics(
            thickness: thickness,
            length: length,
            spacing: 5,
            cornerInset: cornerInset,
            dockGap: edgeGap,
            fontSize: fontSize,
            stack: stack
        )
    }

    /// Distance between two consecutive tab origins along the edge.
    public var step: CGFloat {
        if stack.isEnabled {
            return max(length * (1 - stack.overlapFraction), 6)
        }
        return length + spacing
    }

    /// How much extra room a rotated, staggered stack needs around itself.
    public var stackPadding: CGFloat {
        guard stack.isEnabled else { return 0 }
        let rotation = abs(stack.rotationDegrees) * .pi / 180
        let rotated = abs(length * cos(rotation)) + abs(thickness * sin(rotation))
        return max(0, rotated - length) + abs(stack.stagger)
    }
}

/// Overlapping "stack of bookmarks" look.
public struct StackStyle: Sendable, Equatable {
    public var isEnabled: Bool
    /// Fraction of a tab hidden behind the next one, 0…0.8.
    public var overlapFraction: CGFloat
    /// Slant of the stack, in degrees. The first tab is drawn at 0° and the
    /// slant accumulates towards the end of the run.
    public var rotationDegrees: CGFloat
    /// Perpendicular offset applied per tab, creating the layered look.
    public var stagger: CGFloat

    public init(
        isEnabled: Bool = true,
        overlapFraction: CGFloat = 0.34,
        rotationDegrees: CGFloat = -5,
        stagger: CGFloat = 2.5
    ) {
        self.isEnabled = isEnabled
        self.overlapFraction = min(max(overlapFraction, 0), 0.8)
        self.rotationDegrees = min(max(rotationDegrees, -25), 25)
        self.stagger = min(max(stagger, -12), 12)
    }

    public static let plain = StackStyle(isEnabled: false, overlapFraction: 0, rotationDegrees: 0, stagger: 0)
}

// MARK: - Placement

/// One placed tab.
public struct TagPlacement: Sendable, Equatable {
    /// Index into the project list.
    public var index: Int
    public var slot: EdgeSlot
    /// Frame in screen coordinates, before rotation.
    public var frame: CGRect
    /// Rotation applied around the frame's centre, in degrees.
    public var rotationDegrees: CGFloat
    /// Stacking order: higher is drawn on top (and hit first).
    public var zIndex: Int
    /// How far the tag is layered into the screen (positive = inward). The
    /// view applies this as a visual offset; the panel is sized to include it
    /// so a layered tag is never clipped.
    public var perpendicularOffset: CGFloat

    public init(
        index: Int,
        slot: EdgeSlot,
        frame: CGRect,
        rotationDegrees: CGFloat = 0,
        zIndex: Int = 0,
        perpendicularOffset: CGFloat = 0
    ) {
        self.index = index
        self.slot = slot
        self.frame = frame
        self.rotationDegrees = rotationDegrees
        self.zIndex = zIndex
        self.perpendicularOffset = perpendicularOffset
    }
}

/// Caps on how many tags are drawn at all, and how many share one slot.
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

// MARK: - Layout mode

/// Where the user wants the tags to live.
public struct LayoutMode: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        /// Follow the Dock: use the free side of the Dock's own edge, overflow
        /// to the other side of that edge.
        case dockAdaptive = "dock-adaptive"
        /// Split evenly across both slots of the Dock's edge.
        case dockSplit = "dock-split"
        /// Ignore the Dock's edge: the user picks the edge, the anchor and an
        /// extra offset. The Dock is still avoided when it shares that edge.
        case fixedEdge = "fixed-edge"
    }

    public enum Anchor: String, Sendable, CaseIterable {
        case start
        case center
        case end
    }

    public var kind: Kind
    public var edge: DockEdge
    public var anchor: Anchor
    /// Extra offset along the edge, in points.
    public var offset: CGFloat

    public init(
        kind: Kind = .dockAdaptive,
        edge: DockEdge = .bottom,
        anchor: Anchor = .start,
        offset: CGFloat = 0
    ) {
        self.kind = kind
        self.edge = edge
        self.anchor = anchor
        self.offset = offset
    }

    public static let dockAdaptive = LayoutMode()
}

// MARK: - Plan

/// Everything the window layer needs in order to draw the tabs.
public struct EdgeLayoutPlan: Sendable, Equatable {
    public var edge: DockEdge
    public var metrics: TabMetrics
    public var placements: [TagPlacement]
    /// Projects that did not fit (or were hidden by the limits).
    public var overflowCount: Int
    /// The free ranges each slot drew from, for diagnostics and Settings.
    public var slotRanges: [EdgeSlot: ClosedRange<CGFloat>]
    /// Union of all placements (rotation included), used to size the panel.
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

    /// Placement that owns a point, honouring stacking order.
    public func placement(at point: CGPoint) -> TagPlacement? {
        placements
            .sorted { $0.zIndex > $1.zIndex }
            .first { $0.frame.insetBy(dx: -1, dy: -1).contains(point) }
    }
}
