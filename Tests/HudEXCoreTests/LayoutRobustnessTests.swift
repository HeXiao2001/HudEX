import XCTest
@testable import HudEXCore

/// Layout must never trap, whatever the Dock geometry says: the Dock's length is
/// user-calibratable and only estimated, so inverted ranges are reachable.
///
/// A `Fatal error: Range requires lowerBound <= upperBound` raised from here is
/// what once took the whole app down — and, because the bad calibration was
/// stored in the preferences, kept it down on every relaunch.
final class LayoutRobustnessTests: XCTestCase {
    private let screen = ScreenBounds(
        frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
        visibleFrame: CGRect(x: 54, y: 0, width: 1416, height: 923)
    )

    private var modes: [LayoutMode] {
        [
            LayoutMode(),
            LayoutMode(kind: .dockSplit),
            LayoutMode(kind: .fixedEdge, edge: .left, anchor: .start),
            LayoutMode(kind: .fixedEdge, edge: .right, anchor: .center),
            LayoutMode(kind: .fixedEdge, edge: .bottom, anchor: .end)
        ]
    }

    func testAbsurdDockGeometryNeverTraps() {
        var placed = 0

        for edge in [DockEdge.left, .right, .bottom] {
            for mode in modes {
                for start in stride(from: CGFloat(-400), through: 2400, by: 200) {
                    for length in [CGFloat(0), 1, 60, 900, 4000] {
                        for size in [CGFloat(12), 24, 54, 240] {
                            let metrics = TabMetrics.make(
                                dockThickness: 54,
                                protrusionOverride: size,
                                lengthOverride: size * 2
                            )
                            let dock = DockBounds(
                                edge: edge,
                                thickness: 54,
                                occupiedStart: start,
                                occupiedEnd: start + length,
                                isPresent: length > 0
                            )

                            for count in [0, 1, 5, 40] {
                                let plan = EdgeLayoutEngine.plan(
                                    projectCount: count,
                                    metrics: metrics,
                                    screen: screen,
                                    dock: dock,
                                    mode: mode
                                )
                                placed += plan.placements.count
                                XCTAssertEqual(
                                    plan.placements.count + plan.overflowCount,
                                    count,
                                    "every project is either placed or counted as overflow"
                                )
                                for placement in plan.placements {
                                    XCTAssertGreaterThan(placement.frame.width, 0)
                                    XCTAssertGreaterThan(placement.frame.height, 0)
                                    XCTAssertTrue(
                                        plan.boundingBox.contains(placement.frame),
                                        "\(placement.frame) escapes the panel \(plan.boundingBox)"
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(placed, 100, "the sweep should actually place tags")
    }

    func testTinyScreenNeverTraps() {
        let tiny = ScreenBounds(
            frame: CGRect(x: 0, y: 0, width: 60, height: 60),
            visibleFrame: CGRect(x: 0, y: 0, width: 60, height: 40)
        )
        for edge in [DockEdge.left, .right, .bottom] {
            for start in stride(from: CGFloat(-50), through: 200, by: 25) {
                _ = EdgeLayoutEngine.plan(
                    projectCount: 6,
                    metrics: TabMetrics.make(dockThickness: 54),
                    screen: tiny,
                    dock: DockBounds(
                        edge: edge,
                        thickness: 54,
                        occupiedStart: start,
                        occupiedEnd: start + 20
                    )
                )
            }
        }
    }

    /// The exact geometry that used to crash: a Dock starting above the first
    /// usable point, so there is no room before it.
    func testDockOverlappingTheWholeEdge() {
        let metrics = TabMetrics.make(dockThickness: 54)
        for start in stride(from: CGFloat(0), through: 200, by: 10) {
            let dock = DockBounds(
                edge: .left,
                thickness: 54,
                occupiedStart: start,
                occupiedEnd: start + 1600
            )
            let plan = EdgeLayoutEngine.plan(
                projectCount: 4,
                metrics: metrics,
                screen: screen,
                dock: dock
            )
            XCTAssertEqual(plan.placements.count + plan.overflowCount, 4)
        }
    }
}
