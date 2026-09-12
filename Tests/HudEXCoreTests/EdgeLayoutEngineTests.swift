import XCTest
@testable import HudEXCore

final class EdgeLayoutEngineTests: XCTestCase {
    private let screen = ScreenBounds(
        frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
        visibleFrame: CGRect(x: 54, y: 0, width: 1416, height: 923)
    )

    private func metrics(fontSize: CGFloat? = nil) -> TabMetrics {
        TabMetrics.make(dockThickness: 54, fontSizeOverride: fontSize)
    }

    // MARK: - Left Dock

    func testLeftDockPrimarySlotStartsAtBottomAndGrowsUp() {
        let dock = DockBounds(
            edge: .left,
            thickness: 54,
            occupiedStart: 162,
            occupiedEnd: 794,
            source: .preferences
        )
        let plan = EdgeLayoutEngine.plan(
            projectCount: 3,
            metrics: metrics(),
            screen: screen,
            dock: dock
        )

        XCTAssertEqual(plan.placements.count, 3)
        XCTAssertEqual(plan.overflowCount, 0)
        XCTAssertTrue(plan.placements.allSatisfy { $0.slot == .primary })

        let first = plan.placements[0].frame
        let second = plan.placements[1].frame
        XCTAssertEqual(first.minX, 0, "tab must hug the screen edge")
        XCTAssertEqual(first.width, 54, "tab thickness must equal the Dock thickness")
        XCTAssertEqual(first.minY, 8, accuracy: 0.01, "first tab sits at the bottom inset")
        XCTAssertGreaterThan(second.minY, first.minY, "tabs grow upward")
        XCTAssertLessThanOrEqual(plan.placements.last!.frame.maxY, dock.occupiedStart)
    }

    func testLeftDockOverflowGoesToTheTopSlot() {
        let dock = DockBounds(
            edge: .left,
            thickness: 54,
            occupiedStart: 420,
            occupiedEnd: 560,
            source: .preferences
        )
        let plan = EdgeLayoutEngine.plan(
            projectCount: 30,
            metrics: metrics(),
            screen: screen,
            dock: dock
        )

        let primary = plan.placements.filter { $0.slot == .primary }
        let secondary = plan.placements.filter { $0.slot == .secondary }

        XCTAssertFalse(primary.isEmpty)
        XCTAssertGreaterThan(secondary.count, 1, "overflow must use the top slot")
        XCTAssertEqual(plan.overlapCount, 0)
        XCTAssertTrue(primary.allSatisfy { $0.frame.maxY <= dock.occupiedStart })
        XCTAssertTrue(secondary.allSatisfy { $0.frame.minY >= dock.occupiedEnd })
        XCTAssertTrue(secondary.allSatisfy { $0.frame.maxY <= screen.visibleFrame.maxY }, "never cover the menu bar")

        // Secondary grows downward: the first overflow tab is the topmost.
        XCTAssertGreaterThan(secondary[0].frame.minY, secondary[1].frame.minY)
    }

    func testNoTabEverOverlapsTheDock() {
        for start in stride(from: 60, through: 700, by: 40) {
            let dock = DockBounds(
                edge: .left,
                thickness: 54,
                occupiedStart: CGFloat(start),
                occupiedEnd: CGFloat(start) + 200,
                source: .preferences
            )
            let plan = EdgeLayoutEngine.plan(projectCount: 20, metrics: metrics(), screen: screen, dock: dock)
            for placement in plan.placements {
                XCTAssertFalse(
                    placement.frame.intersects(CGRect(x: 0, y: dock.occupiedStart, width: 54, height: 200)),
                    "placement overlaps the Dock for start=\(start)"
                )
            }
        }
    }

    func testTabsDoNotOverlapEachOther() {
        let dock = DockBounds(edge: .left, thickness: 54, occupiedStart: 300, occupiedEnd: 700)
        let plan = EdgeLayoutEngine.plan(projectCount: 12, metrics: metrics(), screen: screen, dock: dock)
        for (index, first) in plan.placements.enumerated() {
            for second in plan.placements.dropFirst(index + 1) {
                XCTAssertFalse(first.frame.intersects(second.frame))
            }
        }
    }

    // MARK: - Right Dock

    func testRightDockHugsRightEdgeAndGrowsUp() {
        let dock = DockBounds(edge: .right, thickness: 54, occupiedStart: 200, occupiedEnd: 800)
        let plan = EdgeLayoutEngine.plan(projectCount: 3, metrics: metrics(), screen: screen, dock: dock)

        let first = plan.placements[0].frame
        XCTAssertEqual(first.maxX, screen.frame.maxX)
        XCTAssertEqual(first.minY, 8, accuracy: 0.01)
        XCTAssertTrue(plan.placements.allSatisfy { $0.frame.maxY <= dock.occupiedStart })
    }

    // MARK: - Bottom Dock

    func testBottomDockPrimarySlotStartsAtLeftAndGrowsRight() {
        let dock = DockBounds(edge: .bottom, thickness: 54, occupiedStart: 450, occupiedEnd: 1020)
        let plan = EdgeLayoutEngine.plan(projectCount: 3, metrics: metrics(), screen: screen, dock: dock)

        let first = plan.placements[0].frame
        let second = plan.placements[1].frame
        XCTAssertEqual(first.minY, 0, "tab must hug the bottom edge")
        XCTAssertEqual(first.height, 54, "tab height must equal the Dock thickness")
        XCTAssertEqual(first.minX, 8, accuracy: 0.01)
        XCTAssertGreaterThan(second.minX, first.minX, "tabs grow to the right")
    }

    func testBottomDockOverflowGoesToTheRightSlot() {
        let dock = DockBounds(edge: .bottom, thickness: 54, occupiedStart: 200, occupiedEnd: 1270)
        let plan = EdgeLayoutEngine.plan(projectCount: 12, metrics: metrics(), screen: screen, dock: dock)

        let primary = plan.placements.filter { $0.slot == .primary }
        let secondary = plan.placements.filter { $0.slot == .secondary }
        XCTAssertFalse(primary.isEmpty)
        XCTAssertFalse(secondary.isEmpty)
        XCTAssertTrue(primary.allSatisfy { $0.frame.maxX <= dock.occupiedStart })
        XCTAssertTrue(secondary.allSatisfy { $0.frame.minX >= dock.occupiedEnd })
        XCTAssertTrue(secondary.allSatisfy { $0.frame.maxX <= screen.frame.maxX })
    }

    // MARK: - Tab sizing

    func testTabThicknessNeverExceedsDockThickness() {
        for thickness in stride(from: 16, through: 140, by: 4) {
            let metrics = TabMetrics.make(dockThickness: CGFloat(thickness))
            XCTAssertLessThanOrEqual(metrics.thickness, max(CGFloat(thickness), TabMetrics.minimumThickness))
            XCTAssertGreaterThanOrEqual(metrics.fontSize, TabMetrics.minimumFontSize)
            XCTAssertLessThanOrEqual(metrics.fontSize, TabMetrics.maximumFontSize)
        }
    }

    func testFontSizeIsClampedAndThicknessCapped() {
        let tiny = TabMetrics.make(dockThickness: 10)
        XCTAssertEqual(tiny.fontSize, TabMetrics.minimumFontSize)
        XCTAssertEqual(tiny.thickness, TabMetrics.minimumThickness)

        let huge = TabMetrics.make(dockThickness: 400)
        XCTAssertEqual(huge.fontSize, TabMetrics.maximumFontSize)
        XCTAssertEqual(huge.thickness, TabMetrics.maximumThickness)
    }

    func testOverflowCountWhenSpaceRunsOut() {
        let dock = DockBounds(edge: .left, thickness: 54, occupiedStart: 200, occupiedEnd: 700)
        let plan = EdgeLayoutEngine.plan(projectCount: 200, metrics: metrics(), screen: screen, dock: dock)
        XCTAssertGreaterThan(plan.overflowCount, 0)
        XCTAssertEqual(plan.placements.count + plan.overflowCount, 200)
    }

    func testEmptyProjectList() {
        let plan = EdgeLayoutEngine.plan(
            projectCount: 0,
            metrics: metrics(),
            screen: screen,
            dock: DockBounds(edge: .bottom, thickness: 54, occupiedStart: 400, occupiedEnd: 1000)
        )
        XCTAssertTrue(plan.placements.isEmpty)
        XCTAssertEqual(plan.boundingBox, .zero)
    }

    func testAbsentDockUsesBothHalvesWithoutOverlap() {
        let plan = EdgeLayoutEngine.plan(
            projectCount: 40,
            metrics: metrics(),
            screen: screen,
            dock: .absent(edge: .left)
        )
        let primary = plan.placements.filter { $0.slot == .primary }
        let secondary = plan.placements.filter { $0.slot == .secondary }
        XCTAssertFalse(primary.isEmpty)
        XCTAssertFalse(secondary.isEmpty)
        XCTAssertLessThanOrEqual(primary.map(\.frame.maxY).max() ?? 0, secondary.map(\.frame.minY).min() ?? 0)
    }

    // MARK: - User limits and manual sizes

    func testMaximumTagCountHidesTheRest() {
        let dock = DockBounds(edge: .left, thickness: 54, occupiedStart: 162, occupiedEnd: 794)
        let plan = EdgeLayoutEngine.plan(
            projectCount: 5,
            metrics: metrics(),
            screen: screen,
            dock: dock,
            limits: TagLimits(maxTags: 2, maxTagsPerSlot: 0)
        )
        XCTAssertEqual(plan.placements.count, 2)
        XCTAssertEqual(plan.overflowCount, 3)
    }

    func testPerSlotLimitOverflowsToTheSecondSlot() {
        let dock = DockBounds(edge: .left, thickness: 54, occupiedStart: 162, occupiedEnd: 794)
        let plan = EdgeLayoutEngine.plan(
            projectCount: 6,
            metrics: metrics(),
            screen: screen,
            dock: dock,
            limits: TagLimits(maxTags: 0, maxTagsPerSlot: 2)
        )
        XCTAssertEqual(plan.placements.filter { $0.slot == .primary }.count, 2)
        XCTAssertEqual(plan.placements.filter { $0.slot == .secondary }.count, 2)
        XCTAssertEqual(plan.overflowCount, 2)
    }

    func testManualTagSizeOverrides() {
        let metrics = TabMetrics.make(
            dockThickness: 54,
            fontSizeOverride: nil,
            protrusionOverride: 34,
            lengthOverride: 18
        )
        XCTAssertEqual(metrics.thickness, 34)
        XCTAssertEqual(metrics.length, 18)

        let dock = DockBounds(edge: .bottom, thickness: 54, occupiedStart: 450, occupiedEnd: 1020)
        let plan = EdgeLayoutEngine.plan(projectCount: 1, metrics: metrics, screen: screen, dock: dock)
        let frame = plan.placements[0].frame
        XCTAssertEqual(frame.height, 34)
        XCTAssertEqual(frame.width, 18)
    }

    func testManualSizeIsStillClamped() {
        let tiny = TabMetrics.make(dockThickness: 54, protrusionOverride: 4)
        XCTAssertEqual(tiny.thickness, TabMetrics.minimumThickness)

        let huge = TabMetrics.make(dockThickness: 54, protrusionOverride: 400)
        XCTAssertEqual(huge.thickness, TabMetrics.maximumThickness)
    }

    func testUnlimitedLimitsKeepEverything() {
        let dock = DockBounds(edge: .bottom, thickness: 54, occupiedStart: 450, occupiedEnd: 1020)
        let plan = EdgeLayoutEngine.plan(
            projectCount: 3,
            metrics: metrics(),
            screen: screen,
            dock: dock,
            limits: .unlimited
        )
        XCTAssertEqual(plan.placements.count, 3)
        XCTAssertEqual(plan.overflowCount, 0)
    }

    // MARK: - Layout modes

    func testFixedEdgeIgnoresTheDockSide() {
        // Dock on the left, but the user asked for tags centred on the right edge.
        let dock = DockBounds(edge: .left, thickness: 54, occupiedStart: 162, occupiedEnd: 794)
        let mode = LayoutMode(kind: .fixedEdge, edge: .right, anchor: .center, offset: 0)
        let plan = EdgeLayoutEngine.plan(
            projectCount: 3,
            metrics: metrics(),
            screen: screen,
            dock: dock,
            mode: mode
        )

        XCTAssertEqual(plan.edge, .right)
        XCTAssertEqual(plan.placements.count, 3)
        for placement in plan.placements {
            XCTAssertEqual(placement.frame.maxX, screen.frame.maxX, "tags hug the right edge")
            XCTAssertGreaterThanOrEqual(
                placement.frame.minX,
                dock.thickness,
                "the left Dock band is untouched"
            )
        }
        // Centred: the run straddles the middle of the free edge.
        let middle = plan.placements.map(\.frame.midY).reduce(0, +) / CGFloat(plan.placements.count)
        XCTAssertEqual(middle, screen.visibleFrame.midY, accuracy: 60)
    }

    func testFixedEdgeOnAnotherEdgeUsesTheWholeRange() {
        let dock = DockBounds(edge: .left, thickness: 54, occupiedStart: 162, occupiedEnd: 794)
        let mode = LayoutMode(kind: .fixedEdge, edge: .bottom, anchor: .start, offset: 0)
        let plan = EdgeLayoutEngine.plan(
            projectCount: 2,
            metrics: metrics(),
            screen: screen,
            dock: dock,
            mode: mode
        )
        XCTAssertEqual(plan.placements.first?.frame.minX ?? -1, 8, accuracy: 0.01)
        XCTAssertTrue(plan.placements.allSatisfy { $0.slot == .primary })
    }

    func testFixedEdgeStillAvoidsTheDockOnTheSameEdge() {
        let dock = DockBounds(edge: .bottom, thickness: 54, occupiedStart: 450, occupiedEnd: 1020)
        let mode = LayoutMode(kind: .fixedEdge, edge: .bottom, anchor: .start, offset: 0)
        let plan = EdgeLayoutEngine.plan(
            projectCount: 4,
            metrics: metrics(),
            screen: screen,
            dock: dock,
            mode: mode
        )
        for placement in plan.placements {
            XCTAssertLessThanOrEqual(placement.frame.maxX, dock.occupiedStart)
        }
    }

    func testDockSplitUsesBothSides() {
        let dock = DockBounds(edge: .left, thickness: 54, occupiedStart: 430, occupiedEnd: 530)
        let plan = EdgeLayoutEngine.plan(
            projectCount: 6,
            metrics: metrics(),
            screen: screen,
            dock: dock,
            mode: LayoutMode(kind: .dockSplit)
        )
        let primary = plan.placements.filter { $0.slot == .primary }
        let secondary = plan.placements.filter { $0.slot == .secondary }
        XCTAssertEqual(primary.count, 3)
        XCTAssertEqual(secondary.count, 3)
        XCTAssertTrue(primary.allSatisfy { $0.frame.maxY <= dock.occupiedStart })
        XCTAssertTrue(secondary.allSatisfy { $0.frame.minY >= dock.occupiedEnd })
    }

    func testDockAdaptiveFillsPrimaryFirst() {
        let dock = DockBounds(edge: .left, thickness: 54, occupiedStart: 430, occupiedEnd: 530)
        let plan = EdgeLayoutEngine.plan(
            projectCount: 3,
            metrics: metrics(),
            screen: screen,
            dock: dock,
            mode: LayoutMode(kind: .dockAdaptive)
        )
        XCTAssertTrue(plan.placements.allSatisfy { $0.slot == .primary })
    }

    // MARK: - Stacking

    func testStackedTabsOverlapAndKeepDrawingOrder() {
        let stacked = TabMetrics.make(dockThickness: 54, stack: StackStyle(isEnabled: true, overlapFraction: 0.5, rotationDegrees: -6, stagger: 3))
        let dock = DockBounds(edge: .left, thickness: 54, occupiedStart: 500, occupiedEnd: 800)
        let plan = EdgeLayoutEngine.plan(projectCount: 4, metrics: stacked, screen: screen, dock: dock)

        XCTAssertEqual(plan.placements.count, 4)
        // Overlapping: the step is half the tab length, so frames do intersect.
        let first = plan.placements[0].frame
        let second = plan.placements[1].frame
        XCTAssertTrue(first.intersects(second))
        XCTAssertEqual(second.minY - first.minY, stacked.length * 0.5, accuracy: 0.01)

        // Later tabs are drawn on top.
        XCTAssertEqual(plan.placements.map(\.zIndex), [0, 1, 2, 3])
        XCTAssertEqual(plan.placements[0].rotationDegrees, 0, accuracy: 0.001)
        XCTAssertEqual(plan.placements[3].rotationDegrees, -6, accuracy: 0.001)

        // The panel box grows to hold the rotated stack.
        XCTAssertLessThan(plan.boundingBox.minX, first.minX)
    }

    func testStackedHitTestingPrefersTheTopmostTag() {
        let stacked = TabMetrics.make(dockThickness: 54, stack: StackStyle(isEnabled: true, overlapFraction: 0.5, rotationDegrees: 0, stagger: 0))
        let dock = DockBounds(edge: .left, thickness: 54, occupiedStart: 500, occupiedEnd: 800)
        let plan = EdgeLayoutEngine.plan(projectCount: 3, metrics: stacked, screen: screen, dock: dock)
        let overlapPoint = CGPoint(x: 10, y: plan.placements[1].frame.minY + 1)
        XCTAssertEqual(plan.placement(at: overlapPoint)?.index, 1)
    }

    func testPlainStackKeepsTabsApart() {
        let plan = EdgeLayoutEngine.plan(
            projectCount: 3,
            metrics: metrics(),
            screen: screen,
            dock: DockBounds(edge: .left, thickness: 54, occupiedStart: 500, occupiedEnd: 800)
        )
        XCTAssertEqual(plan.placements.map(\.rotationDegrees), [0, 0, 0])
        for (index, first) in plan.placements.enumerated() {
            for second in plan.placements.dropFirst(index + 1) {
                XCTAssertFalse(first.frame.intersects(second.frame))
            }
        }
    }
}

private extension EdgeLayoutPlan {
    /// Number of pairs of overlapping placements (must always be zero).
    var overlapCount: Int {
        var overlaps = 0
        for (index, first) in placements.enumerated() {
            for second in placements.dropFirst(index + 1) where first.frame.intersects(second.frame) {
                overlaps += 1
            }
        }
        return overlaps
    }
}