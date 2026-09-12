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

    /// Draws *all* visible panels into one image, positioned exactly as they
    /// are on screen. This is the only way to check how the tag and the card
    /// meet when they live in different windows.
    static func captureScene(_ label: String) {
        guard let directory else { return }
        let windows = NSApp.windows.filter { $0.isVisible && $0.frame.width > 1 && $0.frame.height > 1 }
        guard !windows.isEmpty else { return }

        let union = windows.reduce(CGRect.null) { $0.union($1.frame) }
        guard !union.isNull, union.width < 4000, union.height < 4000 else { return }

        let image = NSImage(size: union.size)
        image.lockFocus()
        NSColor.clear.set()
        NSRect(origin: .zero, size: union.size).fill()
        for window in windows {
            guard let view = window.contentView else { continue }
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let cgImage = rep.cgImage else { continue }
            let frame = window.frame
            // Both the canvas and the window frames use AppKit's bottom-left
            // origin, so no flip is needed; the image then matches the screen.
            let rect = NSRect(
                x: frame.minX - union.minX,
                y: frame.minY - union.minY,
                width: frame.width,
                height: frame.height
            )
            NSGraphicsContext.current?.cgContext.draw(cgImage, in: rect)
        }
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return }
        let name = String(format: "%@-scene-%.0fx%.0f.png", label, union.width, union.height)
        try? data.write(to: directory.appendingPathComponent(name))
        Log.trace("snapshot: scene \(name)")
    }

    /// Captures after the next run loop pass, so the views have been drawn.
    static func captureSoon(_ label: String) {
        guard isEnabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            capture(label)
            captureScene(label)
        }
    }
}
