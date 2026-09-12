import CoreGraphics
import Foundation

/// Where the hover card goes, for every edge and every corner.
///
/// One solver for all cases: the card is pushed *away* from the screen edge the
/// tags sit on (left edge → card to the right, right edge → left, bottom → up),
/// it is clamped into the visible area so it can never cover the Dock or the
/// menu bar, and — in the skeuomorphic style — the punched hole and the curved
/// connector are derived from the same numbers, so the line always starts at
/// the hole and ends on the card.
public struct PreviewAnchor: Sendable, Equatable {
    /// The card itself.
    public var cardFrame: CGRect
    /// The punched hole in the tag, in screen coordinates.
    public var holeCenter: CGPoint
    /// The hole in the card, where the string arrives. Aligned with the line,
    /// so both ends of the string are punched.
    public var cardHoleCenter: CGPoint
    public var holeRadius: CGFloat
    /// Connector: start (on the tag's edge, at the hole's rim), end (on the
    /// card edge) and the two control points of a cubic Bézier. The curve is
    /// what makes the card look tied to its tag rather than floating.
    public var connectorStart: CGPoint
    public var connectorEnd: CGPoint
    public var connectorControl1: CGPoint
    public var connectorControl2: CGPoint
    /// Frame of the panel that draws the card *and* the connector.
    public var panelFrame: CGRect
    /// Direction the card opens in.
    public var edge: DockEdge

    /// Fallback when the caller has no painted placement: the midpoint of the
    /// tag's card-facing edge.
    static func defaultEdgePoint(of tagFrame: CGRect, edge: DockEdge) -> CGPoint {
        switch edge {
        case .left: return CGPoint(x: tagFrame.maxX, y: tagFrame.midY)
        case .right: return CGPoint(x: tagFrame.minX, y: tagFrame.midY)
        case .bottom: return CGPoint(x: tagFrame.midX, y: tagFrame.maxY)
        }
    }

    /// The card's own punch hole: inside the paper, near the edge that faces
    /// the tag, level with the tag's hole whenever that fits on the card.
    static func cardHole(in card: CGRect, near point: CGPoint, edge: DockEdge) -> CGPoint {
        switch edge {
        case .left:
            return CGPoint(
                x: card.minX + cardHoleInset,
                y: clamp(point.y, card.minY + cardHoleInset, card.maxY - cardHoleInset)
            )
        case .right:
            return CGPoint(
                x: card.maxX - cardHoleInset,
                y: clamp(point.y, card.minY + cardHoleInset, card.maxY - cardHoleInset)
            )
        case .bottom:
            return CGPoint(
                x: clamp(point.x, card.minX + cardHoleInset, card.maxX - cardHoleInset),
                y: card.minY + cardHoleInset
            )
        }
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        min(max(value, low), max(low, high))
    }

    /// Distance the card's hole sits inside its edge.
    public static let cardHoleInset: CGFloat = 11

    /// How one string hangs: direction, amplitude and whether it has a single
    /// arc or an S-bend. Derived from a stable seed so it never changes while
    /// the pointer rests on the tag.
    public struct StringShape: Sendable, Equatable {
        public var firstStop: CGFloat
        public var secondStop: CGFloat
        public var bow1: CGFloat
        public var bow2: CGFloat

        public init(seed: UInt64, length: CGFloat) {
            var generator = SplitMix64(seed)
            let direction: CGFloat = generator.nextUnit() < 0.5 ? -1 : 1
            let amplitude: CGFloat = 5 + CGFloat(generator.nextUnit()) * 9
            let isSShape: Bool = generator.nextUnit() < 0.45
            let firstStop: CGFloat = 0.22 + CGFloat(generator.nextUnit()) * 0.18
            let secondStop: CGFloat = 0.62 + CGFloat(generator.nextUnit()) * 0.18
            let lengthScale: CGFloat = min(max(length / 40, 0.85), 1.3)
            let scale: CGFloat = amplitude * lengthScale

            self.firstStop = firstStop
            self.secondStop = secondStop
            if isSShape {
                // Alternating bows: the string snakes on its way across.
                let firstBow: CGFloat = scale * direction
                let secondBow: CGFloat = -scale * CGFloat(0.55 + generator.nextUnit() * 0.45) * direction
                bow1 = firstBow
                bow2 = secondBow
            } else {
                // One arc: the second control is always at least as far out as
                // the first, so the curve cannot flatten out.
                let sag: CGFloat = scale * direction
                let secondBow: CGFloat = sag * CGFloat(0.9 + generator.nextUnit() * 0.4)
                bow1 = sag
                bow2 = secondBow
            }
        }

        /// A deterministic, well-spread generator — no global RNG state.
        struct SplitMix64 {
            private var state: UInt64

            init(_ seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 0x1234_5678 }

            mutating func next() -> UInt64 {
                state = state &+ 0x9E37_79B9_7F4A_7C15
                var z = state
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                return z ^ (z >> 31)
            }

            /// A value in 0..<1.
            mutating func nextUnit() -> Double {
                Double(next() >> 11) / Double(1 << 53)
            }
        }
    }

    /// Bounding box of the connector path (control points included — a curve
    /// stays inside its control polygon, so the panel can never clip it).
    public var connectorBounds: CGRect {
        let minX = min(connectorStart.x, connectorEnd.x, connectorControl1.x, connectorControl2.x)
        let maxX = max(connectorStart.x, connectorEnd.x, connectorControl1.x, connectorControl2.x)
        let minY = min(connectorStart.y, connectorEnd.y, connectorControl1.y, connectorControl2.y)
        let maxY = max(connectorStart.y, connectorEnd.y, connectorControl1.y, connectorControl2.y)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public static let cardGap: CGFloat = 12
    /// Gap left for the connector line when the card is joined to the tag. It
    /// has to be wide enough for the curve to actually read as a curve.
    public static let connectorGap: CGFloat = 34
    public static let margin: CGFloat = 8

    /// Solves the card placement.
    ///
    /// - Parameters:
    ///   - tagFrame: the tag the pointer is on, in screen coordinates.
    ///   - holeEdgePoint: the exact point where the tag's card-facing edge
    ///     crosses its centre line, painted state included. The string starts
    ///     here, so there is no gap and no overlap.
    ///   - edge: the edge the *tags* live on (not necessarily the Dock's edge).
    ///   - cardSize: the size the card wants to be.
    ///   - visible: the screen's visible frame (Dock and menu bar excluded).
    ///   - usesConnector: skeuomorphic style joins card and tag with a line.
    /// Air between the tag and the start of the connector. Zero: the string has
    /// to come out of the hole, not float next to the tag.
    public static let connectorClearance: CGFloat = 0

    public static func solve(
        tagFrame: CGRect,
        holeEdgePoint: CGPoint? = nil,
        edge: DockEdge,
        cardSize: CGSize,
        visible: CGRect,
        usesConnector: Bool,
        /// Stable per-project seed: every string hangs a little differently,
        /// but the same tag always hangs the same way (no jitter on hover).
        seed: UInt64 = 0
    ) -> PreviewAnchor {
        let gap = usesConnector ? connectorGap : cardGap

        var card = CGRect(origin: .zero, size: cardSize)
        switch edge {
        case .left:
            card.origin.x = tagFrame.maxX + gap
            card.origin.y = tagFrame.midY - cardSize.height / 2
        case .right:
            card.origin.x = tagFrame.minX - gap - cardSize.width
            card.origin.y = tagFrame.midY - cardSize.height / 2
        case .bottom:
            card.origin.x = tagFrame.midX - cardSize.width / 2
            card.origin.y = tagFrame.maxY + gap
        }

        // Keep the card fully inside the usable area: never over the Dock band,
        // never over the menu bar, never off screen.
        let minX = visible.minX + margin
        let maxX = visible.maxX - cardSize.width - margin
        let minY = visible.minY + margin
        let maxY = visible.maxY - cardSize.height - margin
        card.origin.x = min(max(card.origin.x, minX), max(minX, maxX))
        card.origin.y = min(max(card.origin.y, minY), max(minY, maxY))
        card.origin.x = card.origin.x.rounded()
        card.origin.y = card.origin.y.rounded()

        // The hole is punched in the tag's card-facing edge, so the tag's hole
        // and the start of the string are the same point.
        let holeRadius: CGFloat = 3.5
        let edgePoint = holeEdgePoint ?? Self.defaultEdgePoint(of: tagFrame, edge: edge)
        let hole = edgePoint

        // The string arrives at the card's own punch hole, which sits *inside*
        // the paper (like a hole in a page) rather than straddling the edge.
        let cardHole = Self.cardHole(in: card, near: hole, edge: edge)
        let end = cardHole

        // Starts exactly on the tag's painted edge: no gap, no overlap.
        let start = edgePoint

        // A wide S-curve: both control points are pulled most of the way
        // across the gap, which is what makes the string read as a curve
        // instead of a slightly slanted rod.
        // Control points stay *between* the two ends along the gap axis, so the
        // curve is monotone and smooth. The sideways offsets come from the
        // tag's own seed, so one string arcs gently, another sags, another
        // snakes — like real string rather than one shape stamped out.
        let across = edge == .bottom ? (end.y - start.y) : (end.x - start.x)
        let drop = edge == .bottom ? (end.x - start.x) : (end.y - start.y)
        let shape = StringShape(seed: seed, length: hypot(across, drop))

        let control1: CGPoint
        let control2: CGPoint
        let first = shape.firstStop
        let second = shape.secondStop
        switch edge {
        case .left, .right:
            control1 = CGPoint(x: start.x + across * first, y: start.y + shape.bow1)
            control2 = CGPoint(x: start.x + across * second, y: end.y + shape.bow2)
        case .bottom:
            control1 = CGPoint(x: start.x + shape.bow1, y: start.y + across * first)
            control2 = CGPoint(x: end.x + shape.bow2, y: start.y + across * second)
        }

        var panel = card
        if usesConnector {
            let connector = CGRect(
                x: min(start.x, end.x, control1.x, control2.x),
                y: min(start.y, end.y, control1.y, control2.y),
                width: abs(max(start.x, end.x, control1.x, control2.x) - min(start.x, end.x, control1.x, control2.x)),
                height: abs(max(start.y, end.y, control1.y, control2.y) - min(start.y, end.y, control1.y, control2.y))
            )
            panel = card.union(connector).insetBy(dx: -holeRadius - 1, dy: -holeRadius - 1)

            // The panel must never sit on top of the tag it belongs to,
            // otherwise the pointer would enter the panel instead of staying on
            // the tag and the hover would flicker.
            switch edge {
            case .left:
                panel.origin.x = max(panel.origin.x, start.x)
                panel.size.width = max(1, panel.maxX - panel.origin.x)
            case .right:
                panel.size.width = max(1, start.x - panel.origin.x)
            case .bottom:
                panel.origin.y = max(panel.origin.y, start.y)
                panel.size.height = max(1, panel.maxY - panel.origin.y)
            }
        } else {
            panel = panel.insetBy(dx: -holeRadius - 1, dy: -holeRadius - 1)
        }

        return PreviewAnchor(
            cardFrame: card,
            holeCenter: hole,
            cardHoleCenter: cardHole,
            holeRadius: holeRadius,
            connectorStart: start,
            connectorEnd: end,
            connectorControl1: control1,
            connectorControl2: control2,
            panelFrame: panel,
            edge: edge
        )
    }
}
