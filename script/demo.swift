#!/usr/bin/env swift
//
// Sweeps the pointer along the HudEX bookmarks so a screen recording shows
// every hover card in turn. Nothing in the app changes: this only moves the
// cursor, exactly like a person would.
//
//   swift script/demo.swift [passes] [pause-seconds]
//
// The sweep follows the bookmark panel it finds on screen, so it works with the
// Dock on the left, on the right, or at the bottom.
//
import AppKit
import CoreGraphics

let arguments = CommandLine.arguments.dropFirst()
let passes = max(1, Int(arguments.first ?? "3") ?? 3)
let pause = Double(arguments.dropFirst().first ?? "1.0") ?? 1.0

let screenHeight = NSScreen.screens.first?.frame.maxY ?? 0

/// All on-screen windows of the running HudEX, in AppKit coordinates.
func hudexWindowFrames() -> [CGRect] {
    guard let app = NSRunningApplication
        .runningApplications(withBundleIdentifier: "dev.hex.hudex")
        .first else {
        FileHandle.standardError.write(Data("HudEX is not running.\n".utf8))
        exit(1)
    }
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.compactMap { window -> CGRect? in
        guard (window[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier,
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
              rect.width >= 20, rect.height >= 20 else { return nil }
        return CGRect(
            x: rect.minX,
            y: screenHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}

/// The bookmark panel: the small, thin one (the card is much bigger).
func bookmarkPanel() -> CGRect {
    let frames = hudexWindowFrames()
    let panels = frames.filter { min($0.width, $0.height) <= 120 }
    guard let panel = panels.min(by: { $0.width * $0.height < $1.width * $1.height }) else {
        FileHandle.standardError.write(Data("No HudEX bookmark panel on screen.\n".utf8))
        exit(1)
    }
    return panel
}

func warp(to point: CGPoint) {
    CGWarpMouseCursorPosition(CGPoint(x: point.x, y: screenHeight - point.y))
    CGAssociateMouseAndMouseCursorPosition(1)
}

let panel = bookmarkPanel()
let vertical = panel.height >= panel.width
// Sweep just inside the panel's long axis, in the middle of the bookmarks.
let inner: CGFloat = 14
let start: CGPoint
let end: CGPoint
if vertical {
    let x = panel.minX + min(inner, panel.width / 2)
    start = CGPoint(x: x, y: panel.maxY - 10)
    end = CGPoint(x: x, y: panel.minY + 10)
} else {
    let y = panel.minY + min(inner, panel.height / 2)
    start = CGPoint(x: panel.minX + 10, y: y)
    end = CGPoint(x: panel.maxX - 10, y: y)
}

print("Sweeping the bookmarks \(passes)× (\(Int(panel.width))×\(Int(panel.height)) panel)")
for pass in 1...passes {
    // A short pause away from the panel so each pass starts from "nothing open".
    warp(to: CGPoint(x: panel.midX + 400, y: panel.midY))
    Thread.sleep(forTimeInterval: 0.6)

    for step in 0...120 {
        let t = CGFloat(step) / 120
        warp(to: CGPoint(x: start.x + (end.x - start.x) * t,
                         y: start.y + (end.y - start.y) * t))
        Thread.sleep(forTimeInterval: 0.055)
    }
    Thread.sleep(forTimeInterval: pause)
    print("  pass \(pass) done")
}
print("Finished — the pointer is left near the bookmarks.")
