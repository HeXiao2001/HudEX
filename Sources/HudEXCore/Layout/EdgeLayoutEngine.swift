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
                let frame = frame(
                    forOffset: offset,
                    in: spec.range,
                    growth: spec.growth,
                    metrics: metrics,
                    screen: screen,
                    edge: edge
                )
                placements.append(
                    TagPlacement(
                        index: index,
                        slot: slot,
                        frame: frame,
                        rotationDegrees: rotation(forOffset: offset, count: visibleCount, stack: metrics.stack),
                        zIndex: index
                    )
                )
                index += 1
            }
        }

        let overflow = max(0, projectCount - index)
        let box = placements.reduce(CGRect.null) { partial, placement in
            partial.union(visualBounds(of: placement.frame, metrics: metrics))
        }

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

    private static func rotation(forOffset offset: Int, count: Int, stack: StackStyle) -> CGFloat {
        guard stack.isEnabled, stack.rotationDegrees != 0, count > 1 else { return 0 }
        let progress = CGFloat(min(offset, count - 1)) / CGFloat(count - 1)
        return stack.rotationDegrees * progress
    }

    /// Frame plus the room its rotation and stagger need, used to size panels.
    static func visualBounds(of frame: CGRect, metrics: TabMetrics) -> CGRect {
        let padding = metrics.stackPadding
        guard padding > 0 else { return frame }
        return frame.insetBy(dx: -padding, dy: -padding)
    }
}
