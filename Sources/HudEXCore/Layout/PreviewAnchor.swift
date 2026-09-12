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
    /// The punched hole, in screen coordinates (inside the tag).
    public var holeCenter: CGPoint
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

    /// Bounding box of the connector path (control points included, so the
    /// curve can never leave the panel).
    public var connectorBounds: CGRect {
        let minX = min(connectorStart.x, connectorEnd.x, connectorControl1.x, connectorControl2.x)
        let maxX = max(connectorStart.x, connectorEnd.x, connectorControl1.x, connectorControl2.x)
        let minY = min(connectorStart.y, connectorEnd.y, connectorControl1.y, connectorControl2.y)
        let maxY = max(connectorStart.y, connectorEnd.y, connectorControl1.y, connectorControl2.y)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public static let cardGap: CGFloat = 12
    /// Gap left for the connector line when the card is joined to the tag.
    public static let connectorGap: CGFloat = 14
    public static let margin: CGFloat = 8

    /// Solves the card placement.
    ///
    /// - Parameters:
    ///   - tagFrame: the tag the pointer is on, in screen coordinates.
    ///   - edge: the edge the *tags* live on (not necessarily the Dock's edge).
    ///   - cardSize: the size the card wants to be.
    ///   - visible: the screen's visible frame (Dock and menu bar excluded).
    ///   - usesConnector: skeuomorphic style joins card and tag with a line.
    public static func solve(
        tagFrame: CGRect,
        edge: DockEdge,
        cardSize: CGSize,
        visible: CGRect,
        usesConnector: Bool
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

        var end = hole
        switch edge {
        case .left:
            end = CGPoint(x: card.minX, y: card.midY)
        case .right:
            end = CGPoint(x: card.maxX, y: card.midY)
        case .bottom:
            end = CGPoint(x: card.midX, y: card.minY)
        }

        // The line is drawn by the card's panel and may not cover the tag, so it
        // starts exactly on the tag's card-facing edge — which is the hole's rim.
        let start: CGPoint
        switch edge {
        case .left: start = CGPoint(x: tagFrame.maxX, y: hole.y)
        case .right: start = CGPoint(x: tagFrame.minX, y: hole.y)
        case .bottom: start = CGPoint(x: hole.x, y: tagFrame.maxY)
        }

        // A shallow S-curve reads as a natural "string" rather than a rod.
        let control1: CGPoint
        let control2: CGPoint
        switch edge {
        case .left:
            let dx = (end.x - start.x) * 0.45
            control1 = CGPoint(x: start.x + dx * 0.35, y: start.y)
            control2 = CGPoint(x: end.x - dx * 0.55, y: end.y)
        case .right:
            let dx = (start.x - end.x) * 0.45
            control1 = CGPoint(x: start.x - dx * 0.35, y: start.y)
            control2 = CGPoint(x: end.x + dx * 0.55, y: end.y)
        case .bottom:
            let dy = (end.y - start.y) * 0.45
            control1 = CGPoint(x: start.x, y: start.y + dy * 0.35)
            control2 = CGPoint(x: end.x, y: end.y - dy * 0.55)
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
                panel.origin.x = max(panel.origin.x, tagFrame.maxX)
                panel.size.width = max(1, panel.maxX - panel.origin.x)
            case .right:
                let limit = tagFrame.minX
                panel.size.width = max(1, limit - panel.origin.x)
            case .bottom:
                panel.origin.y = max(panel.origin.y, tagFrame.maxY)
                panel.size.height = max(1, panel.maxY - panel.origin.y)
            }
        } else {
            panel = panel.insetBy(dx: -holeRadius - 1, dy: -holeRadius - 1)
        }

        return PreviewAnchor(
            cardFrame: card,
            holeCenter: hole,
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
