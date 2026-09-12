import AppKit
import CoreGraphics
import Foundation

/// Development helper: captures HudEX's own panels to PNG files so the visuals
/// can be inspected without a screen recorder.
///
/// Opt-in through `HUDEX_SNAPSHOT=<directory>`; nothing runs (and nothing is
/// linked into the hot path) unless that variable is set. Capturing your own
/// windows needs no TCC permission.
@MainActor
enum SnapshotDebugger {
    private static var directory: URL? {
        guard let path = ProcessInfo.processInfo.environment["HUDEX_SNAPSHOT"] else { return nil }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var isEnabled: Bool { directory != nil }

    /// Captures every visible window of this app.
    static func capture(_ label: String) {
        guard let directory else { return }
        let windows = NSApp.windows.filter { $0.isVisible && $0.frame.width > 1 && $0.frame.height > 1 }
        var written = 0
        for (index, window) in windows.enumerated() {
            guard let view = window.contentView else { continue }
            // Rendering the view hierarchy needs no screen-capture permission
            // (unlike CGWindowListCreateImage, which macOS 26 removed anyway).
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { continue }
            let name = String(format: "%@-%02d-%.0fx%.0f.png", label, index, window.frame.width, window.frame.height)
            if (try? data.write(to: directory.appendingPathComponent(name))) != nil { written += 1 }
        }
        _ = written
        Log.trace("snapshot: wrote \(written) windows as \(label)")
    }

    /// Captures after the next run loop pass, so the views have been drawn.
    static func captureSoon(_ label: String) {
        guard isEnabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            capture(label)
        }
    }
}
