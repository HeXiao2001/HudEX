import CoreGraphics
import Foundation

/// The subset of `com.apple.dock` preferences HudEX reads.
///
/// Reading the Dock's own preferences is a public, permission-free way to learn
/// the edge, thickness and approximate length of the Dock — including while it
/// is auto-hidden, when `NSScreen.visibleFrame` no longer reserves any space.
public struct DockPreferences: Sendable, Equatable {
    public enum Pinning: String, Sendable {
        case start
        case middle
        case end
    }

    public var orientation: DockEdge?
    public var autoHide: Bool
    public var tileSize: CGFloat
    public var magnification: Bool
    public var largeSize: CGFloat
    public var pinning: Pinning
    /// Number of pinned application tiles.
    public var persistentAppCount: Int
    /// Number of pinned "other" tiles (folders, Trash …).
    public var persistentOtherCount: Int

    public init(
        orientation: DockEdge?,
        autoHide: Bool,
        tileSize: CGFloat,
        magnification: Bool,
        largeSize: CGFloat,
        pinning: Pinning,
        persistentAppCount: Int,
        persistentOtherCount: Int
    ) {
        self.orientation = orientation
        self.autoHide = autoHide
        self.tileSize = tileSize
        self.magnification = magnification
        self.largeSize = largeSize
        self.pinning = pinning
        self.persistentAppCount = persistentAppCount
        self.persistentOtherCount = persistentOtherCount
    }

    /// Values used when the Dock preferences cannot be read at all.
    public static let fallback = DockPreferences(
        orientation: nil,
        autoHide: false,
        tileSize: 48,
        magnification: false,
        largeSize: 64,
        pinning: .middle,
        persistentAppCount: 10,
        persistentOtherCount: 1
    )

    /// Parses `orientation`, which is a string on modern macOS.
    public static func parseOrientation(_ raw: String?) -> DockEdge? {
        switch raw?.lowercased() {
        case "left": return .left
        case "right": return .right
        case "bottom": return .bottom
        default: return nil
        }
    }

    /// `pinning` is a string on modern macOS and a legacy integer before that.
    public static func parsePinning(_ raw: Any?) -> Pinning {
        if let string = raw as? String {
            return Pinning(rawValue: string) ?? .middle
        }
        if let number = raw as? Int {
            switch number {
            case -1: return .start
            case 1: return .end
            default: return .middle
            }
        }
        return .middle
    }
}

/// Pure geometry for the Dock's reserved rectangle.
///
/// Everything here is a function of the screen and the Dock preferences, which
/// makes it fully unit-testable and keeps the AppKit layer to a thin query.
public enum DockGeometryEstimator {
    /// Padding the Dock adds around its tiles: measured on macOS 26, a 34 pt
    /// tile size reserves a 54 pt band.
    public static let bandPadding: CGFloat = 20
    /// Horizontal spacing between two tiles.
    public static let iconSpacing: CGFloat = 10
    /// Extra length reserved to absorb separators and rounding.
    public static let lengthSafetyMargin: CGFloat = 16
    /// A Dock never occupies more than this fraction of the edge.
    public static let maximumLengthFraction: CGFloat = 0.92

    /// Thickness of the Dock band, from the tile size.
    public static func thickness(for preferences: DockPreferences) -> CGFloat {
        max(24, preferences.tileSize + bandPadding)
    }

    /// Approximate length of the Dock along its edge.
    ///
    /// Only *pinned* tiles are counted: on macOS 26 a running application that
    /// is not pinned does not add a tile, which was verified against a live
    /// Dock (13 pinned tiles, many running apps, 13 visible icons).
    public static func length(
        for preferences: DockPreferences,
        axisLength: CGFloat
    ) -> CGFloat {
        let tileCount = max(1, preferences.persistentAppCount + preferences.persistentOtherCount + 1)
        let raw = CGFloat(tileCount) * (preferences.tileSize + iconSpacing) + lengthSafetyMargin
        let maximum = axisLength * maximumLengthFraction
        return min(raw, maximum)
    }

    /// Where the Dock sits along its edge, honouring the pinning preference.
    public static func occupiedRange(
        for preferences: DockPreferences,
        axisRange: ClosedRange<CGFloat>,
        length: CGFloat
    ) -> ClosedRange<CGFloat> {
        let axisLength = axisRange.upperBound - axisRange.lowerBound
        guard length < axisLength else { return axisRange }
        switch preferences.pinning {
        case .start:
            return axisRange.lowerBound...(axisRange.lowerBound + length)
        case .end:
            return (axisRange.upperBound - length)...axisRange.upperBound
        case .middle:
            let center = (axisRange.lowerBound + axisRange.upperBound) / 2
            let start = max(axisRange.lowerBound, center - length / 2)
            return start...min(axisRange.upperBound, start + length)
        }
    }

    /// Builds the Dock bounds for one screen.
    ///
    /// - Parameters:
    ///   - reservedBand: thickness measured from `NSScreen.visibleFrame`, when
    ///     the Dock actually reserves space. Exact when > 0.
    ///   - edge: which edge the Dock is on.
    ///   - screen: the screen frame (full frame, AppKit coordinates).
    ///   - manualLength: a user calibration, when set.
    public static func bounds(
        edge: DockEdge,
        preferences: DockPreferences,
        screen: ScreenBounds,
        reservedBand: CGFloat,
        isVisible: Bool,
        isPresent: Bool,
        manualThickness: CGFloat? = nil,
        manualLength: CGFloat? = nil
    ) -> DockBounds {
        guard isPresent else {
            return DockBounds.absent(edge: edge)
        }

        let thickness: CGFloat
        let source: DockBounds.Source
        if let manualThickness, manualThickness > 0 {
            thickness = manualThickness
            source = .preferences
        } else if reservedBand > 1 {
            thickness = reservedBand
            source = .reservedBand
        } else {
            // Auto-hidden Dock: `visibleFrame` no longer reserves the band, but
            // the Dock still needs the same space when it slides out.
            thickness = self.thickness(for: preferences)
            source = .preferences
        }

        let axisRange: ClosedRange<CGFloat>
        switch edge {
        case .left, .right:
            axisRange = screen.frame.minY...screen.frame.maxY
        case .bottom:
            axisRange = screen.frame.minX...screen.frame.maxX
        }

        let axisLength = axisRange.upperBound - axisRange.lowerBound
        let length = manualLength.flatMap { $0 > 0 ? $0 : nil }
            ?? self.length(for: preferences, axisLength: axisLength)
        let range = occupiedRange(for: preferences, axisRange: axisRange, length: length)

        return DockBounds(
            edge: edge,
            thickness: thickness,
            occupiedStart: range.lowerBound,
            occupiedEnd: range.upperBound,
            isVisible: isVisible,
            isPresent: true,
            source: source
        )
    }
}
