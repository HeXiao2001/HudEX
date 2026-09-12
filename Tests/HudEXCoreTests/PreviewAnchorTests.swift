import XCTest
@testable import HudEXCore

final class PreviewAnchorTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
    private let visible = CGRect(x: 54, y: 0, width: 1416, height: 923)
    private let card = CGSize(width: 300, height: 240)

    func testCardOpensAwayFromTheEdge() {
        let left = PreviewAnchor.solve(
            tagFrame: CGRect(x: 0, y: 8, width: 54, height: 25),
            edge: .left,
            cardSize: card,
            visible: visible,
            usesConnector: true
        )
        XCTAssertGreaterThanOrEqual(left.cardFrame.minX, 54, "left edge → card to the right")
        XCTAssertEqual(left.cardFrame.minX, 54 + PreviewAnchor.connectorGap, accuracy: 0.01)

        let right = PreviewAnchor.solve(
            tagFrame: CGRect(x: 1416, y: 8, width: 54, height: 25),
            edge: .right,
            cardSize: card,
            visible: visible,
            usesConnector: true
        )
        XCTAssertLessThanOrEqual(right.cardFrame.maxX, 1416, "right edge → card to the left")

        let bottom = PreviewAnchor.solve(
            tagFrame: CGRect(x: 8, y: 0, width: 25, height: 54),
            edge: .bottom,
            cardSize: card,
            visible: visible,
            usesConnector: true
        )
        XCTAssertGreaterThanOrEqual(bottom.cardFrame.minY, 54, "bottom edge → card above")
    }

    func testCardIsAlwaysInsideTheVisibleFrame() {
        let edges: [DockEdge] = [.left, .right, .bottom]
        let positions: [CGRect] = [
            CGRect(x: 0, y: 0, width: 54, height: 25),          // bottom-left corner
            CGRect(x: 0, y: 440, width: 54, height: 25),        // middle
            CGRect(x: 0, y: 898, width: 54, height: 25),        // top-left corner
            CGRect(x: 1416, y: 0, width: 54, height: 25),
            CGRect(x: 1416, y: 898, width: 54, height: 25),
            CGRect(x: 0, y: 0, width: 25, height: 54),
            CGRect(x: 1445, y: 0, width: 25, height: 54)
        ]
        for edge in edges {
            for tag in positions {
                let anchor = PreviewAnchor.solve(
                    tagFrame: tag, edge: edge, cardSize: card, visible: visible, usesConnector: true
                )
                XCTAssertTrue(
                    visible.insetBy(dx: -0.5, dy: -0.5).contains(anchor.cardFrame),
                    "card \(anchor.cardFrame) escapes the usable area for tag \(tag) on \(edge)"
                )
            }
        }
    }

    func testConnectorStartsAtTheHoleAndEndsOnTheCard() {
        for edge in [DockEdge.left, .right, .bottom] {
            let tag = CGRect(x: edge == .right ? 1416 : 0, y: 0, width: 54, height: 25)
            let anchor = PreviewAnchor.solve(
                tagFrame: tag, edge: edge, cardSize: card, visible: visible, usesConnector: true
            )
            let distance = hypot(
                anchor.connectorStart.x - anchor.holeCenter.x,
                anchor.connectorStart.y - anchor.holeCenter.y
            )
            XCTAssertLessThanOrEqual(
                distance,
                anchor.holeRadius + 4,
                "the line must start at the hole, not somewhere else"
            )

            switch edge {
            case .left: XCTAssertEqual(anchor.connectorEnd.x, anchor.cardFrame.minX, accuracy: 0.01)
            case .right: XCTAssertEqual(anchor.connectorEnd.x, anchor.cardFrame.maxX, accuracy: 0.01)
            case .bottom: XCTAssertEqual(anchor.connectorEnd.y, anchor.cardFrame.minY, accuracy: 0.01)
            }
        }
    }

    func testPanelContainsTheWholeCurve() {
        for edge in [DockEdge.left, .right, .bottom] {
            let anchor = PreviewAnchor.solve(
                tagFrame: CGRect(x: edge == .right ? 1416 : 0, y: 300, width: 54, height: 25),
                edge: edge,
                cardSize: card,
                visible: visible,
                usesConnector: true
            )
            XCTAssertTrue(
                anchor.panelFrame.contains(anchor.connectorBounds),
                "the Bézier (including control points) must fit inside the panel"
            )
            XCTAssertTrue(anchor.panelFrame.contains(anchor.cardFrame))
            // The hole lives inside the tag, so it is *adjacent* to the panel:
            // the gap between them is the hole's own inset, not empty space.
            let gapX = max(anchor.panelFrame.minX - anchor.holeCenter.x,
                           anchor.holeCenter.x - anchor.panelFrame.maxX, 0)
            let gapY = max(anchor.panelFrame.minY - anchor.holeCenter.y,
                           anchor.holeCenter.y - anchor.panelFrame.maxY, 0)
            XCTAssertLessThanOrEqual(
                max(gapX, gapY),
                anchor.holeRadius + 6,
                "the hole must sit right next to the panel"
            )
        }
    }

    func testPanelNeverCoversItsOwnTag() {
        for edge in [DockEdge.left, .right, .bottom] {
            let tag = CGRect(x: edge == .right ? 1416 : 0, y: 8, width: 54, height: 25)
            let anchor = PreviewAnchor.solve(
                tagFrame: tag, edge: edge, cardSize: card, visible: visible, usesConnector: true
            )
            let overlapping = anchor.panelFrame.intersection(tag)
            XCTAssertTrue(
                overlapping.isNull || overlapping.width < 0.5 || overlapping.height < 0.5,
                "panel \(anchor.panelFrame) covers its tag \(tag) on \(edge)"
            )
        }
    }

    func testHoleStaysInsideTheTagSoBothCornersStayVisible() {
        let tag = CGRect(x: 0, y: 8, width: 54, height: 25)
        let anchor = PreviewAnchor.solve(
            tagFrame: tag, edge: .left, cardSize: card, visible: visible, usesConnector: true
        )
        XCTAssertGreaterThan(anchor.holeCenter.x - anchor.holeRadius, tag.minX)
        XCTAssertLessThan(anchor.holeCenter.x + anchor.holeRadius, tag.maxX)
        XCTAssertGreaterThan(anchor.holeCenter.y - anchor.holeRadius, tag.minY)
        XCTAssertLessThan(anchor.holeCenter.y + anchor.holeRadius, tag.maxY)
    }

    func testWithoutConnectorTheCardKeepsAGap() {
        let tag = CGRect(x: 0, y: 8, width: 54, height: 25)
        let anchor = PreviewAnchor.solve(
            tagFrame: tag, edge: .left, cardSize: card, visible: visible, usesConnector: false
        )
        XCTAssertEqual(anchor.cardFrame.minX, tag.maxX + PreviewAnchor.cardGap, accuracy: 0.01)
    }
}

final class VisualEnvelopeTests: XCTestCase {
    private let screen = ScreenBounds(
        frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
        visibleFrame: CGRect(x: 54, y: 0, width: 1416, height: 923)
    )

    private func stackedMetrics(overlap: CGFloat = 0.34, rotation: CGFloat = -5, stagger: CGFloat = 2.5) -> TabMetrics {
        TabMetrics.make(
            dockThickness: 54,
            stack: StackStyle(isEnabled: true, overlapFraction: overlap, rotationDegrees: rotation, stagger: stagger)
        )
    }

    /// The old bug: a rotated / layered tag was painted outside the panel and
    /// its rounded corners were cut off.
    func testPanelContainsEveryRotatedAndLayeredTag() {
        for edge in [DockEdge.left, .right, .bottom] {
            let dock = DockBounds(
                edge: edge,
                thickness: 54,
                occupiedStart: edge == .bottom ? 400 : 200,
                occupiedEnd: edge == .bottom ? 1000 : 760
            )
            let plan = EdgeLayoutEngine.plan(
                projectCount: 6,
                metrics: stackedMetrics(),
                screen: screen,
                dock: dock
            )
            XCTAssertEqual(plan.edge, edge)

            for placement in plan.placements {
                var visual = EdgeLayoutEngine.rotatedBounds(of: placement.frame, degrees: placement.rotationDegrees)
                // Apply the same layering the view applies.
                switch edge {
                case .left: visual.size.width += placement.perpendicularOffset
                case .right: visual.origin.x -= placement.perpendicularOffset; visual.size.width += placement.perpendicularOffset
                case .bottom: visual.size.height += placement.perpendicularOffset
                }
                XCTAssertTrue(
                    plan.boundingBox.insetBy(dx: -0.5, dy: -0.5).contains(visual),
                    "tag \(placement.index) escapes the panel on \(edge): \(visual) vs \(plan.boundingBox)"
                )
            }
        }
    }

    func testEnvelopeIncludesTheHoverLift() {
        let dock = DockBounds(edge: .left, thickness: 54, occupiedStart: 200, occupiedEnd: 760)
        let plan = EdgeLayoutEngine.plan(
            projectCount: 4,
            metrics: stackedMetrics(),
            screen: screen,
            dock: dock
        )
        let last = plan.placements.last!
        let lifted = EdgeLayoutEngine.rotatedBounds(of: last.frame, degrees: last.rotationDegrees)
        // The hovered tag swings back outwards by one stagger.
        XCTAssertTrue(plan.boundingBox.insetBy(dx: -0.5, dy: -0.5).contains(lifted))
        XCTAssertGreaterThan(plan.boundingBox.maxX, plan.placements[0].frame.maxX)
    }

    func testLayeringGrowsWithTheStack() {
        let dock = DockBounds(edge: .left, thickness: 54, occupiedStart: 200, occupiedEnd: 900)
        let plan = EdgeLayoutEngine.plan(
            projectCount: 4,
            metrics: stackedMetrics(stagger: 3),
            screen: screen,
            dock: dock
        )
        XCTAssertEqual(plan.placements.map(\.perpendicularOffset), [0, 3, 6, 9])
    }

    func testPlainStackHasNoLayeringAndNoRotation() {
        let dock = DockBounds(edge: .left, thickness: 54, occupiedStart: 200, occupiedEnd: 900)
        let plan = EdgeLayoutEngine.plan(
            projectCount: 3,
            metrics: TabMetrics.make(dockThickness: 54, stack: .plain),
            screen: screen,
            dock: dock
        )
        XCTAssertEqual(plan.placements.map(\.perpendicularOffset), [0, 0, 0])
        XCTAssertEqual(plan.placements.map(\.rotationDegrees), [0, 0, 0])
    }
}

final class PriorityTests: XCTestCase {
    func testPriorityParsing() {
        XCTAssertEqual(ProjectPriority.parse("高"), .high)
        XCTAssertEqual(ProjectPriority.parse("high"), .high)
        XCTAssertEqual(ProjectPriority.parse("普通"), .normal)
        XCTAssertEqual(ProjectPriority.parse("低"), .low)
        XCTAssertNil(ProjectPriority.parse("随便"))
        XCTAssertNil(ProjectPriority.parse(nil))
    }

    func testPriorityIsReadFromTheDocument() {
        let text = """
        ## A
        优先级：高
        ### 当前
        a

        ## B
        priority: low
        ### 当前
        b
        """
        let document = MarkdownProjectParser().parse(text)
        XCTAssertEqual(document.projects[0].priority, .high)
        XCTAssertEqual(document.projects[1].priority, .low)
    }

    func testHoleColoursAreDistinct() {
        let light = ProjectPriority.allCases.map { $0.holeColor(isDark: false).hexString }
        XCTAssertEqual(Set(light).count, ProjectPriority.allCases.count)
    }
}
