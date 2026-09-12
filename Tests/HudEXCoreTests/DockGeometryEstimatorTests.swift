import XCTest
@testable import HudEXCore

final class DockGeometryEstimatorTests: XCTestCase {
    private let screen = ScreenBounds(
        frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
        visibleFrame: CGRect(x: 54, y: 0, width: 1416, height: 923)
    )

    private var dockPreferences: DockPreferences {
        DockPreferences(
            orientation: .left,
            autoHide: false,
            tileSize: 34,
            magnification: true,
            largeSize: 59,
            pinning: .middle,
            persistentAppCount: 12,
            persistentOtherCount: 1
        )
    }

    func testReservedBandWinsWhenTheDockReservesSpace() {
        let bounds = DockGeometryEstimator.bounds(
            edge: .left,
            preferences: dockPreferences,
            screen: screen,
            reservedBand: 54,
            isVisible: true,
            isPresent: true
        )
        XCTAssertEqual(bounds.thickness, 54)
        XCTAssertEqual(bounds.source, .reservedBand)
    }

    /// With "Automatically hide and show the Dock" on, macOS stops reserving the
    /// band. The Dock must still be avoided.
    func testAutoHiddenDockKeepsItsReservedThickness() {
        var preferences = dockPreferences
        preferences.autoHide = true

        let bounds = DockGeometryEstimator.bounds(
            edge: .left,
            preferences: preferences,
            screen: screen,
            reservedBand: 0,
            isVisible: false,
            isPresent: true
        )
        XCTAssertEqual(bounds.thickness, 54, "tile size 34 + 20 pt band padding")
        XCTAssertGreaterThan(bounds.occupiedLength, 0)
        XCTAssertEqual(bounds.source, .preferences)
    }

    func testThicknessDerivationMatchesTheLiveDock() {
        // Measured on macOS 26: tilesize 34 → a 54 pt reserved band.
        let preferences = DockPreferences(
            orientation: .bottom,
            autoHide: false,
            tileSize: 34,
            magnification: false,
            largeSize: 64,
            pinning: .middle,
            persistentAppCount: 12,
            persistentOtherCount: 1
        )
        XCTAssertEqual(DockGeometryEstimator.thickness(for: preferences), 54)
    }

    func testPinningPositionsTheOccupiedRange() {
        var preferences = dockPreferences
        preferences.pinning = .start
        let atStart = DockGeometryEstimator.bounds(
            edge: .left,
            preferences: preferences,
            screen: screen,
            reservedBand: 54,
            isVisible: true,
            isPresent: true
        )
        XCTAssertEqual(atStart.occupiedStart, 0, accuracy: 0.01)

        preferences.pinning = .end
        let atEnd = DockGeometryEstimator.bounds(
            edge: .left,
            preferences: preferences,
            screen: screen,
            reservedBand: 54,
            isVisible: true,
            isPresent: true
        )
        XCTAssertEqual(atEnd.occupiedEnd, screen.frame.maxY, accuracy: 0.01)

        preferences.pinning = .middle
        let centered = DockGeometryEstimator.bounds(
            edge: .left,
            preferences: preferences,
            screen: screen,
            reservedBand: 54,
            isVisible: true,
            isPresent: true
        )
        XCTAssertEqual(centered.occupiedStart + centered.occupiedLength / 2, screen.frame.midY, accuracy: 1)
    }

    func testLengthEstimateCountsOnlyPinnedTiles() {
        let length = DockGeometryEstimator.length(for: dockPreferences, axisLength: 956)
        // 13 pinned tiles + 1 separator tile, 34 pt tiles, 10 pt gaps.
        XCTAssertEqual(length, CGFloat(14) * 44 + DockGeometryEstimator.lengthSafetyMargin, accuracy: 0.5)
    }

    func testLengthNeverExceedsTheMaximumFraction() {
        var preferences = dockPreferences
        preferences.persistentAppCount = 200
        let length = DockGeometryEstimator.length(for: preferences, axisLength: 956)
        XCTAssertEqual(length, 956 * DockGeometryEstimator.maximumLengthFraction, accuracy: 0.5)
    }

    func testManualOverridesAreUsed() {
        let bounds = DockGeometryEstimator.bounds(
            edge: .bottom,
            preferences: dockPreferences,
            screen: screen,
            reservedBand: 54,
            isVisible: true,
            isPresent: true,
            manualThickness: 70,
            manualLength: 400
        )
        XCTAssertEqual(bounds.thickness, 70)
        XCTAssertEqual(bounds.occupiedLength, 400, accuracy: 0.5)
    }

    func testAbsentDockIsReportedAsAbsent() {
        let bounds = DockGeometryEstimator.bounds(
            edge: .right,
            preferences: dockPreferences,
            screen: screen,
            reservedBand: 0,
            isVisible: false,
            isPresent: false
        )
        XCTAssertFalse(bounds.isPresent)
        XCTAssertEqual(bounds.occupiedLength, 0)
        XCTAssertEqual(bounds.edge, .right)
    }

    func testPinningParsingHandlesLegacyIntegers() {
        XCTAssertEqual(DockPreferences.parsePinning("start"), .start)
        XCTAssertEqual(DockPreferences.parsePinning("end"), .end)
        XCTAssertEqual(DockPreferences.parsePinning(-1), .start)
        XCTAssertEqual(DockPreferences.parsePinning(1), .end)
        XCTAssertEqual(DockPreferences.parsePinning(nil), .middle)
        XCTAssertEqual(DockPreferences.parsePinning("nonsense"), .middle)
    }

    func testOrientationParsing() {
        XCTAssertEqual(DockPreferences.parseOrientation("bottom"), .bottom)
        XCTAssertEqual(DockPreferences.parseOrientation("LEFT"), .left)
        XCTAssertNil(DockPreferences.parseOrientation("top"))
        XCTAssertNil(DockPreferences.parseOrientation(nil))
    }
}
