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

    /// Point on the card's near edge that is closest to the tag's hole, so the
    /// card's own punched hole lines up with the string.
    static func nearestEdgePoint(of card: CGRect, to point: CGPoint, edge: DockEdge) -> CGPoint {
        switch edge {
        case .left:
            return CGPoint(x: card.minX, y: min(max(point.y, card.minY + cardHoleInset), card.maxY - cardHoleInset))
        case .right:
            return CGPoint(x: card.maxX, y: min(max(point.y, card.minY + cardHoleInset), card.maxY - cardHoleInset))
        case .bottom:
            return CGPoint(x: min(max(point.x, card.minX + cardHoleInset), card.maxX - cardHoleInset), y: card.minY)
        }
    }

    /// Distance the card's hole sits inside its edge.
    public static let cardHoleInset: CGFloat = 9

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
    ///   - tagVisualBounds: the tag as actually painted (rotation and hover
    ///     push included). The connector starts just outside it, so the curve
    ///     never crosses the tag.
    ///   - edge: the edge the *tags* live on (not necessarily the Dock's edge).
    ///   - cardSize: the size the card wants to be.
    ///   - visible: the screen's visible frame (Dock and menu bar excluded).
    ///   - usesConnector: skeuomorphic style joins card and tag with a line.
    /// Air between the tag and the start of the connector. Zero: the string has
    /// to come out of the hole, not float next to the tag.
    public static let connectorClearance: CGFloat = 0

    public static func solve(
        tagFrame: CGRect,
        tagVisualBounds: CGRect? = nil,
        edge: DockEdge,
        cardSize: CGSize,
        visible: CGRect,
        usesConnector: Bool
    ) -> PreviewAnchor {
        let gap = usesConnector ? connectorGap : cardGap
        let visual = tagVisualBounds ?? tagFrame

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

        // The hole sits on the tag's edge that faces the card, just inside the
        // rounded corner so both corners stay visible.
        let holeRadius: CGFloat = 3.5
        let inset = holeRadius + 3
        var hole = CGPoint.zero
        switch edge {
        case .left:
            hole = CGPoint(x: tagFrame.maxX - inset, y: tagFrame.midY)
        case .right:
            hole = CGPoint(x: tagFrame.minX + inset, y: tagFrame.midY)
        case .bottom:
            hole = CGPoint(x: tagFrame.midX, y: tagFrame.maxY - inset)
        }

        // The string arrives at the card's own hole: the nearest point of the
        // card to the hole, so the line stays short and obviously connected.
        let cardHole = Self.nearestEdgePoint(of: card, to: hole, edge: edge)
        var end = cardHole

        // The line is drawn by the card's panel, which sits above the tag's
        // panel: starting it on the tag's *painted* edge (plus a hair) is what
        // keeps the curve off the tag itself.
        let start: CGPoint
        switch edge {
        case .left: start = CGPoint(x: visual.maxX + connectorClearance, y: hole.y)
        case .right: start = CGPoint(x: visual.minX - connectorClearance, y: hole.y)
        case .bottom: start = CGPoint(x: hole.x, y: visual.maxY + connectorClearance)
        }

        // A wide S-curve: both control points are pulled most of the way
        // across the gap, which is what makes the string read as a curve
        // instead of a slightly slanted rod.
        // Even when the two holes sit on the same line, the string should hang
        // rather than be a rod: both control points get the same sideways bow,
        // which keeps the ends exactly on the holes while the middle sags.
        let chord = hypot(end.x - start.x, end.y - start.y)
        let bow = min(max(chord * 0.25, 6), 14)
        let bowOffset: CGPoint
        switch edge {
        case .left, .right: bowOffset = CGPoint(x: 0, y: -bow)
        case .bottom: bowOffset = CGPoint(x: bow, y: 0)
        }

        let control1: CGPoint
        let control2: CGPoint
        let pull: CGFloat = 0.75
        switch edge {
        case .left:
            let dx = end.x - start.x
            control1 = CGPoint(x: start.x + dx * pull, y: start.y + bowOffset.y)
            control2 = CGPoint(x: end.x - dx * pull, y: end.y + bowOffset.y)
        case .right:
            let dx = start.x - end.x
            control1 = CGPoint(x: start.x - dx * pull, y: start.y + bowOffset.y)
            control2 = CGPoint(x: end.x + dx * pull, y: end.y + bowOffset.y)
        case .bottom:
            let dy = end.y - start.y
            control1 = CGPoint(x: start.x + bowOffset.x, y: start.y + dy * pull)
            control2 = CGPoint(x: end.x + bowOffset.x, y: end.y - dy * pull)
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
                panel.origin.x = max(panel.origin.x, visual.maxX + connectorClearance)
                panel.size.width = max(1, panel.maxX - panel.origin.x)
            case .right:
                let limit = visual.minX - connectorClearance
                panel.size.width = max(1, limit - panel.origin.x)
            case .bottom:
                panel.origin.y = max(panel.origin.y, visual.maxY + connectorClearance)
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
