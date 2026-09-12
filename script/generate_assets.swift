#!/usr/bin/env swift
//
// Draws the HudEX app icon, writes a full .iconset, then asks `iconutil` for
// the .icns. Run by script/build_and_run.sh when the icon is missing or out of
// date. Pure CoreGraphics/AppKit, no dependencies.
//
import AppKit
import CoreGraphics
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("script/HudEX.iconset")
let icns = root.appendingPathComponent("script/HudEX.icns")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

/// Draws the icon at a given pixel size.
func drawIcon(size: CGFloat, into context: CGContext) {
    let inset = size * 0.04
    let bounds = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = bounds.width * 0.22

    // Background: dark rounded square, like a modern macOS utility.
    context.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1))
    context.addPath(CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.fillPath()

    // Three solid edge tabs: the product in one picture.
    let colors: [CGColor] = [
        CGColor(red: 0.24, green: 0.72, blue: 0.35, alpha: 1),
        CGColor(red: 0.95, green: 0.78, blue: 0.20, alpha: 1),
        CGColor(red: 0.62, green: 0.64, blue: 0.68, alpha: 1)
    ]
    let tabWidth = bounds.width * 0.32
    let tabHeight = bounds.height * 0.15
    let tabGap = bounds.height * 0.06
    let startX = bounds.minX + bounds.width * 0.16
    var y = bounds.minY + bounds.height * 0.22

    for color in colors.reversed() {
        context.setFillColor(color)
        let rect = CGRect(x: startX, y: y, width: tabWidth, height: tabHeight)
        context.addPath(
            CGPath(roundedRect: rect, cornerWidth: tabHeight * 0.22, cornerHeight: tabHeight * 0.22, transform: nil)
        )
        context.fillPath()
        y += tabHeight + tabGap
    }

    // A bookmark outline, so the icon reads as "bookmarks" even at 16 pt.
    context.setStrokeColor(CGColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1))
    context.setLineWidth(max(1, size * 0.035))
    context.setLineJoin(.round)

    let bookmark = CGMutablePath()
    let bookmarkWidth = bounds.width * 0.26
    let bookmarkHeight = bounds.height * 0.40
    let bookmarkX = bounds.maxX - bounds.width * 0.16 - bookmarkWidth
    let bookmarkTop = bounds.maxY - bounds.height * 0.22
    let bookmarkBottom = bookmarkTop - bookmarkHeight
    let notch = bookmarkHeight * 0.26

    bookmark.move(to: CGPoint(x: bookmarkX, y: bookmarkTop))
    bookmark.addLine(to: CGPoint(x: bookmarkX + bookmarkWidth, y: bookmarkTop))
    bookmark.addLine(to: CGPoint(x: bookmarkX + bookmarkWidth, y: bookmarkBottom))
    bookmark.addLine(to: CGPoint(x: bookmarkX + bookmarkWidth / 2, y: bookmarkBottom + notch))
    bookmark.addLine(to: CGPoint(x: bookmarkX, y: bookmarkBottom))
    bookmark.closeSubpath()

    context.addPath(bookmark)
    context.strokePath()
}

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

for entry in sizes {
    let pixels = entry.pixels
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        FileHandle.standardError.write(Data("cannot create bitmap context\n".utf8))
        exit(1)
    }
    context.setAllowsAntialiasing(true)
    drawIcon(size: CGFloat(pixels), into: context)

    guard let image = context.makeImage() else { continue }
    let representation = NSBitmapImageRep(cgImage: image)
    guard let data = representation.representation(using: .png, properties: [:]) else { continue }
    try data.write(to: iconset.appendingPathComponent("\(entry.name).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "-o", icns.path, iconset.path]
try iconutil.run()
iconutil.waitUntilExit()

if iconutil.terminationStatus == 0 {
    print("HudEX.icns written to \(icns.path)")
} else {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}
