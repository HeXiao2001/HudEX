import CoreGraphics
import Foundation

/// Places tabs in the edge space the Dock does not occupy.
///
/// One engine, three edges, three modes: the slot ranges come from the Dock
/// bounds, the layout mode and the growth direction, so there is no per-edge or
/// per-mode copy of the packing logic.
public enum EdgeLayoutEngine {
    /// A range to pack into plus the direction the run grows in.
    struct SlotSpec: Equatable {
        var range: ClosedRange<CGFloat>
        var growth: GrowthDirection

        var length: CGFloat { range.upperBound - range.lowerBound }
    }

    public static func plan(
        projectCount: Int,
        metrics: TabMetrics,
        screen: ScreenBounds,
        dock: DockBounds,
        limits: TagLimits = .unlimited,
        mode: LayoutMode = .dockAdaptive
    ) -> EdgeLayoutPlan {
        let edge = mode.kind == .fixedEdge ? mode.edge : dock.edge
        guard projectCount > 0 else {
            return EdgeLayoutPlan(
                edge: edge,
                metrics: metrics,
                placements: [],
                overflowCount: 0,
                slotRanges: [:],
                boundingBox: .zero
            )
        }

        let specs = slotSpecs(metrics: metrics, screen: screen, dock: dock, mode: mode)
        let visibleCount = limits.visibleCount(for: projectCount)
        var placements: [TagPlacement] = []
        var index = 0

        // dockSplit fills both slots evenly; the other modes fill the primary
        // slot first and only then use the secondary one.
        let primaryTarget = mode.kind == .dockSplit ? (visibleCount + 1) / 2 : visibleCount

        for slot in [EdgeSlot.primary, .secondary] {
            guard index < visibleCount, let spec = specs[slot] else { continue }
            let capacity = limits.slotCapacity(for: capacity(in: spec.range, metrics: metrics))
            let target = slot == .primary ? min(primaryTarget, visibleCount) : visibleCount
            for offset in 0..<capacity where index < target {
                let frame = alignToEdge(
                    frame(
                        forOffset: offset,
                        in: spec.range,
                        growth: spec.growth,
                        metrics: metrics,
                        screen: screen,
                        edge: edge
                    ),
                    rotationDegrees: rotation(forOffset: offset, count: visibleCount, stack: metrics.stack),
                    edge: edge
                )
                placements.append(
                    TagPlacement(
                        index: index,
                        slot: slot,
                        frame: frame,
                        rotationDegrees: rotation(forOffset: offset, count: visibleCount, stack: metrics.stack),
                        zIndex: index,
                        hoverOffset: hoverOffset(forOffset: offset, stack: metrics.stack)
                    )
                )
                index += 1
            }
        }

        let overflow = max(0, projectCount - index)
        let box = panelBounds(for: placements, metrics: metrics, edge: edge)

        var ranges: [EdgeSlot: ClosedRange<CGFloat>] = [:]
        for (slot, spec) in specs { ranges[slot] = spec.range }

        return EdgeLayoutPlan(
            edge: edge,
            metrics: metrics,
            placements: placements,
            overflowCount: overflow,
            slotRanges: ranges,
            boundingBox: box.isNull ? .zero : box
        )
    }

    // MARK: - Slots

    static func slotSpecs(
        metrics: TabMetrics,
        screen: ScreenBounds,
        dock: DockBounds,
        mode: LayoutMode
    ) -> [EdgeSlot: SlotSpec] {
        let edge = mode.kind == .fixedEdge ? mode.edge : dock.edge
        let segments = freeSegments(edge: edge, metrics: metrics, screen: screen, dock: dock)
        guard !segments.isEmpty else { return [:] }

        switch mode.kind {
        case .dockAdaptive, .dockSplit:
            var specs: [EdgeSlot: SlotSpec] = [
                .primary: SlotSpec(range: segments[0], growth: edge.naturalGrowth)
            ]
            if segments.count > 1 {
                specs[.secondary] = SlotSpec(range: segments[segments.count - 1], growth: edge.naturalGrowth.opposite)
            }
            return specs

        case .fixedEdge:
            switch mode.anchor {
            case .start:
                let primary = shift(segments[0], by: mode.offset)
                var specs: [EdgeSlot: SlotSpec] = [
                    .primary: SlotSpec(range: primary, growth: edge.naturalGrowth)
                ]
                if segments.count > 1 {
                    specs[.secondary] = SlotSpec(range: segments[segments.count - 1], growth: edge.naturalGrowth)
                }
                return specs

            case .end:
                let primary = shift(segments[segments.count - 1], by: -mode.offset)
                var specs: [EdgeSlot: SlotSpec] = [
                    .primary: SlotSpec(range: primary, growth: edge.naturalGrowth.opposite)
                ]
                if segments.count > 1 {
                    specs[.secondary] = SlotSpec(range: segments[0], growth: edge.naturalGrowth.opposite)
                }
                return specs

            case .center:
                let target = segments.max { ($0.upperBound - $0.lowerBound) < ($1.upperBound - $1.lowerBound) } ?? segments[0]
                let needed = metrics.length
                let center = (target.lowerBound + target.upperBound) / 2 + mode.offset
                let start = max(target.lowerBound, min(center - needed / 2, target.upperBound - needed))
                var specs: [EdgeSlot: SlotSpec] = [
                    .primary: SlotSpec(range: start...target.upperBound, growth: edge.naturalGrowth)
                ]
                if segments.count > 1 {
                    let other = segments.first { $0 != target } ?? segments[0]
                    specs[.secondary] = SlotSpec(range: other, growth: edge.naturalGrowth)
                }
                return specs
            }
        }
    }

    /// Free ranges along the edge axis, the Dock's reserved area removed.
    static func freeSegments(
        edge: DockEdge,
        metrics: TabMetrics,
        screen: ScreenBounds,
        dock: DockBounds
    ) -> [ClosedRange<CGFloat>] {
        let axis = axisRange(edge: edge, screen: screen)
        let low = axis.lowerBound + metrics.cornerInset
        let high = axis.upperBound - metrics.cornerInset
        guard high > low else { return [] }

        guard dock.isPresent else {
            // No Dock anywhere: the whole edge is free, split in two so overflow
            // still has somewhere to go.
            let middle = (low + high) / 2
            let gap = metrics.dockGap / 2
            return [low...(middle - gap), (middle + gap)...high]
        }
        guard dock.edge == edge else {
            // The Dock is on another edge: this edge is completely free.
            return [low...high]
        }

        let gap = metrics.dockGap
        var segments: [ClosedRange<CGFloat>] = []
        let before = low...min(high, dock.occupiedStart - gap)
        if before.upperBound - before.lowerBound >= metrics.length {
            segments.append(before)
        }
        let afterLow = max(low, dock.occupiedEnd + gap)
        if high - afterLow >= metrics.length {
            segments.append(afterLow...high)
        }
        return segments
    }

    /// Usable coordinate range on the edge axis (menu bar excluded).
    static func axisRange(edge: DockEdge, screen: ScreenBounds) -> ClosedRange<CGFloat> {
        switch edge {
        case .left, .right:
            let top = screen.hasMenuBar ? screen.visibleFrame.maxY : screen.frame.maxY
            return screen.frame.minY...max(top, screen.frame.minY)
        case .bottom:
            return screen.frame.minX...screen.frame.maxX
        }
    }

    private static func shift(_ range: ClosedRange<CGFloat>, by offset: CGFloat) -> ClosedRange<CGFloat> {
        guard offset != 0 else { return range }
        let length = range.upperBound - range.lowerBound
        let low = max(range.lowerBound, min(range.lowerBound + offset, range.upperBound - length))
        return low...(low + length)
    }

    // MARK: - Packing

    /// How many tabs fit in a range without shrinking or overlapping.
    public static func capacity(in range: ClosedRange<CGFloat>, metrics: TabMetrics) -> Int {
        let available = range.upperBound - range.lowerBound
        guard available >= metrics.length else { return 0 }
        let step = metrics.step
        guard step > 0 else { return 1 }
        return max(1, Int(floor((available - metrics.length) / step)) + 1)
    }

    private static func frame(
        forOffset offset: Int,
        in range: ClosedRange<CGFloat>,
        growth: GrowthDirection,
        metrics: TabMetrics,
        screen: ScreenBounds,
        edge: DockEdge
    ) -> CGRect {
        let step = metrics.step
        let along: CGFloat
        switch growth {
        case .up, .right:
            along = range.lowerBound + CGFloat(offset) * step
        case .down, .left:
            along = range.upperBound - metrics.length - CGFloat(offset) * step
        }

        // Flush with the screen edge. Staggering is a view-layer visual offset;
        // the hit area stays the axis-aligned frame so hover stays predictable.
        let screenFrame = screen.frame
        switch edge {
        case .left:
            return CGRect(x: screenFrame.minX, y: along, width: metrics.thickness, height: metrics.length)
        case .right:
            return CGRect(x: screenFrame.maxX - metrics.thickness, y: along, width: metrics.thickness, height: metrics.length)
        case .bottom:
            return CGRect(x: along, y: screenFrame.minY, width: metrics.length, height: metrics.thickness)
        }
    }

    /// Tags rest on the screen edge; hovering pushes one card towards the
    /// popup by one stagger step. The rest of the stack stays put, so the run
    /// keeps a straight line instead of drifting deeper with every card.
    private static func hoverOffset(forOffset offset: Int, stack: StackStyle) -> CGFloat {
        guard stack.isEnabled else { return 0 }
        return stack.stagger
    }

    private static func rotation(forOffset offset: Int, count: Int, stack: StackStyle) -> CGFloat {
        guard stack.isEnabled, stack.rotationDegrees != 0, count > 1 else { return 0 }
        let progress = CGFloat(min(offset, count - 1)) / CGFloat(count - 1)
        return stack.rotationDegrees * progress
    }

    /// Bounding box of a set of tags including everything they can paint:
    /// rotation, layering and the hover lift. The window layer sizes each panel
    /// with this, so nothing is ever clipped.
    public static func panelBounds(
        for placements: [TagPlacement],
        metrics: TabMetrics,
        edge: DockEdge
    ) -> CGRect {
        let box = placements.reduce(CGRect.null) { partial, placement in
            partial.union(visualBounds(of: placement, metrics: metrics, edge: edge))
        }
        return box.isNull ? .zero : box
    }

    /// Everything a tag can paint: its frame, rotated, layered inward, plus one
    /// extra `stagger` for the hover lift. Panels are sized from this, so a
    /// rotated or lifted tag is never cut off — which is what made the tag's
    /// rounded corners disappear before.
    static func visualBounds(of placement: TagPlacement, metrics: TabMetrics, edge: DockEdge) -> CGRect {
        var box = rotatedBounds(
            of: placement.frame,
            degrees: placement.rotationDegrees,
            anchor: rotationAnchor(for: edge)
        )

        // Room for the hover push (towards the popup) and for the offset a
        // tag travels while it animates there.
        let push = abs(placement.hoverOffset)
        if push > 0 {
            switch edge {
            case .left: box.size.width += push
            case .right: box.origin.x -= push; box.size.width += push
            case .bottom: box.size.height += push
            }
        }

        // A hair of margin so anti-aliased edges are never clipped.
        return box.insetBy(dx: -Self.panelMargin, dy: -Self.panelMargin)
    }

    /// Nudges a rotated tag so its outer edge stays exactly on the screen edge.
    ///
    /// Rotating around the edge midpoint swings the corners about 1.5 pt in or
    /// out; compensating here keeps the whole stack on one line — the tags stay
    /// flush instead of waving along the edge.
    public static func alignToEdge(
        _ frame: CGRect,
        rotationDegrees: CGFloat,
        edge: DockEdge
    ) -> CGRect {
        guard rotationDegrees != 0 else { return frame }
        let rotated = rotatedBounds(of: frame, degrees: rotationDegrees, anchor: rotationAnchor(for: edge))
        switch edge {
        case .left:
            return frame.offsetBy(dx: frame.minX - rotated.minX, dy: 0)
        case .right:
            return frame.offsetBy(dx: frame.maxX - rotated.maxX, dy: 0)
        case .bottom:
            return frame.offsetBy(dx: 0, dy: frame.minY - rotated.minY)
        }
    }

    /// Tags are pinned to the screen edge, so they rotate around that edge:
    /// the stack keeps one straight line instead of fanning out of alignment.
    public static func rotationAnchor(for edge: DockEdge) -> RotationAnchor {
        switch edge {
        case .left: return .minX
        case .right: return .maxX
        case .bottom: return .minY
        }
    }

    /// Which point of the rectangle stays put while it rotates.
    public enum RotationAnchor: Sendable, Equatable {
        case minX
        case maxX
        case minY
    }

    /// Axis-aligned bounds of a rectangle rotated about one of its edges.
    static func rotatedBounds(
        of frame: CGRect,
        degrees: CGFloat,
        anchor: RotationAnchor = .minX
    ) -> CGRect {
        guard degrees != 0 else { return frame }
        let radians = degrees * .pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)

        // Corners relative to the anchor point, rotated, then re-anchored.
        let origin: CGPoint
        switch anchor {
        case .minX: origin = CGPoint(x: frame.minX, y: frame.midY)
        case .maxX: origin = CGPoint(x: frame.maxX, y: frame.midY)
        case .minY: origin = CGPoint(x: frame.midX, y: frame.minY)
        }

        let corners = [
            CGPoint(x: frame.minX, y: frame.minY),
            CGPoint(x: frame.maxX, y: frame.minY),
            CGPoint(x: frame.maxX, y: frame.maxY),
            CGPoint(x: frame.minX, y: frame.maxY)
        ].map { corner -> CGPoint in
            let dx = corner.x - origin.x
            let dy = corner.y - origin.y
            return CGPoint(
                x: origin.x + dx * cosine - dy * sine,
                y: origin.y + dx * sine + dy * cosine
            )
        }

        let xs = corners.map(\.x)
        let ys = corners.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return frame
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Breathing room kept around the tags inside their panel.
    public static let panelMargin: CGFloat = 2
}
