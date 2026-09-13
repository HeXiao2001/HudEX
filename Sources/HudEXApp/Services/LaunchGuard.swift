import AppKit
import Foundation
import HudEXCore

/// Watches over the first seconds of every launch.
///
/// A desktop agent has no window to show that something went wrong, so a crash
/// during startup used to look like "it flashed and disappeared" — and if the
/// bad state lived in the preferences (a hand-calibrated Dock, say), every later
/// launch crashed the same way. This guard:
///
/// * notices that the previous run never reached the "healthy" mark,
/// * drops back to conservative settings when that happens twice in a row,
/// * leaves a short report in `~/Library/Logs/HudEX/` for the person to send,
/// * and tells the caller, so a first recoverable launch can show Settings.
@MainActor
enum LaunchGuard {
    enum Outcome: Equatable {
        case healthy
        /// Two or more launches in a row never became healthy.
        case recovered(attempts: Int, reportURL: URL?)
    }

    private static let attemptsKey = "diagnostics.launchAttempts"
    private static let firstLaunchKey = "diagnostics.firstLaunchDone"
    private static let healthyDelay: TimeInterval = 6

    /// Call as early as possible in `applicationDidFinishLaunching`.
    static func begin() -> Outcome {
        let defaults = UserDefaults.standard
        let previous = defaults.integer(forKey: attemptsKey)
        defaults.set(previous + 1, forKey: attemptsKey)

        var outcome: Outcome = .healthy
        if previous >= 1 {
            // The last run never reported itself healthy: start defensively.
            let report = writeReport(previousAttempts: previous)
            enterSafeMode()
            outcome = .recovered(attempts: previous, reportURL: report)
            Log.app.warning("previous launch did not become healthy; starting in safe mode")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + healthyDelay) {
            markHealthy()
        }
        return outcome
    }

    /// True exactly once, on the very first launch with this preferences file.
    static func consumeFirstLaunch() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: firstLaunchKey) { return false }
        defaults.set(true, forKey: firstLaunchKey)
        return true
    }

    private static func markHealthy() {
        UserDefaults.standard.set(0, forKey: attemptsKey)
    }

    /// The settings most likely to keep a launch from finishing.
    private static func enterSafeMode() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "layout.dockThicknessOverride")
        defaults.removeObject(forKey: "layout.dockLengthOverride")
        defaults.removeObject(forKey: "layout.fixedOffset")
        defaults.set(false, forKey: "appearance.stack.enabled")
        defaults.set(true, forKey: "appearance.menuBarIcon")
        // Let the controller pick the reset up without a relaunch.
        NotificationCenter.default.post(name: .hudexSafeModeApplied, object: nil)
    }

    private static func writeReport(previousAttempts: Int) -> URL? {
        let fm = FileManager.default
        guard let logs = fm.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs/HudEX", isDirectory: true) else { return nil }
        try? fm.createDirectory(at: logs, withIntermediateDirectories: true)

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        var lines = [
            "HudEX launch report",
            "date: \(TimestampFormatter.string(from: Date()))",
            "version: \(version) (\(build))",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "interrupted launches in a row: \(previousAttempts)",
            "safe mode: applied (Dock calibration cleared, stacking off)",
            "",
            "settings:"
        ]
        let interesting = [
            "appearance.style", "layout.kind", "layout.fixedEdge", "layout.fixedAnchor",
            "layout.tabProtrusion", "layout.tabLength", "appearance.fontSize",
            "layout.dockThickness", "layout.dockLength", "source.path"
        ]
        for key in interesting {
            lines.append("  \(key) = \(UserDefaults.standard.object(forKey: key).map { "\($0)" } ?? "—")")
        }
        let reports = crashReports()
        lines.append("")
        lines.append("system crash reports: \(reports.isEmpty ? "none found" : reports.joined(separator: ", "))")

        let url = logs.appendingPathComponent("last-launch.txt")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Recent `HudEX-*.ips` entries, if macOS wrote any.
    static func crashReports(limit: Int = 3) -> [String] {
        let fm = FileManager.default
        guard let dir = fm.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs/DiagnosticReports", isDirectory: true) else { return [] }
        let entries = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return entries
            .filter { $0.lastPathComponent.hasPrefix("HudEX") }
            .sorted { ($0.lastModified ?? .distantPast) > ($1.lastModified ?? .distantPast) }
            .prefix(limit)
            .map(\.lastPathComponent)
    }

    /// Folder holding the report, for "Reveal" buttons.
    static var reportFolder: URL? {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs/HudEX", isDirectory: true)
    }
}

private extension URL {
    var lastModified: Date? {
        (try? resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}

extension Notification.Name {
    /// Posted when the guard cleared risky settings after a bad launch.
    static let hudexSafeModeApplied = Notification.Name("dev.hex.hudex.safeModeApplied")
}
