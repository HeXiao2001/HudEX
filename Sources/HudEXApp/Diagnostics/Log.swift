import Foundation
import os

/// Logging is intentionally sparse: HudEX runs for weeks, so anything per-frame
/// or per-event would flood the log. Release builds therefore only keep
/// warnings, errors and faults.
enum Log {
    private static let subsystem = "dev.hex.hudex"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let markdown = Logger(subsystem: subsystem, category: "markdown")
    static let watcher = Logger(subsystem: subsystem, category: "watcher")
    static let dock = Logger(subsystem: subsystem, category: "dock")
    static let layout = Logger(subsystem: subsystem, category: "layout")
    static let window = Logger(subsystem: subsystem, category: "window")
    static let settings = Logger(subsystem: subsystem, category: "settings")

    /// Opt-in breadcrumb file for interactive debugging (`HUDEX_TRACE=<path>`).
    /// Nothing is written unless the environment variable is set, so a normal
    /// run never touches the disk.
    static func trace(_ message: @autoclosure () -> String) {
        guard let path = ProcessInfo.processInfo.environment["HUDEX_TRACE"] else { return }
        let line = "\(Date().timeIntervalSince1970) \(message())\n"
        let url = URL(fileURLWithPath: path)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    /// Debug-only detail. Compiled out of Release entirely.
    static func debug(_ logger: Logger, _ message: @autoclosure () -> String) {
        #if DEBUG
        let text = message()
        logger.debug("\(text, privacy: .public)")
        #endif
    }
}
