#!/usr/bin/env swift
//
// Draws the background of the drag-to-Applications disk image window.
//
//   swift script/make_dmg_background.swift <output.png> [width] [height]
//
import AppKit
import Foundation

let arguments = CommandLine.arguments
let output = arguments.count > 1 ? arguments[1] : "script/dmg-background.png"
let width = arguments.count > 2 ? CGFloat(Double(arguments[2]) ?? 660) : 660
let height = arguments.count > 3 ? CGFloat(Double(arguments[3]) ?? 420) : 420

// Finder tiles a disk image's background one *pixel* per point, so this has to
// be drawn at the window's own size — a 2× image lands seven times too big,
// which is exactly how the first version came out.
// An explicit bitmap rep: `lockFocus` would honour the display's scale factor
// and quietly hand back a 2× image, which is what threw the layout off.
let pixels = CGSize(width: width, height: height)
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(pixels.width),
    pixelsHigh: Int(pixels.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { exit(1) }
rep.size = NSSize(width: width, height: height)
guard let graphics = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
let context = graphics.cgContext

// Backdrop: a soft vertical gradient, dark enough for white text.
let space = CGColorSpaceCreateDeviceRGB()
let gradient = CGGradient(
    colorsSpace: space,
    colors: [
        NSColor(srgbRed: 0.145, green: 0.165, blue: 0.196, alpha: 1).cgColor,
        NSColor(srgbRed: 0.086, green: 0.098, blue: 0.118, alpha: 1).cgColor
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: height),
    end: CGPoint(x: 0, y: 0),
    options: []
)

func draw(
    _ text: String,
    size: CGFloat,
    weight: NSFont.Weight,
    y: CGFloat,
    alpha: CGFloat = 1,
    tracking: CGFloat = 0
) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor.white.withAlphaComponent(alpha),
        .kern: tracking
    ]
    let string = NSAttributedString(string: text, attributes: attributes)
    let bounds = string.size()
    string.draw(at: NSPoint(x: (width - bounds.width) / 2, y: y))
}

draw("HudEX", size: 19, weight: .semibold, y: height - 38, alpha: 0.95)
draw("DRAG TO APPLICATIONS", size: 9.5, weight: .medium, y: height - 58, alpha: 0.42, tracking: 1.6)

// A long arrow between the two icons.
let arrowY = height * 0.48
context.setStrokeColor(NSColor.white.withAlphaComponent(0.28).cgColor)
context.setLineWidth(2)
context.setLineCap(.round)
context.move(to: CGPoint(x: width * 0.40, y: arrowY))
context.addLine(to: CGPoint(x: width * 0.60, y: arrowY))
context.strokePath()
context.move(to: CGPoint(x: width * 0.57, y: arrowY + 6))
context.addLine(to: CGPoint(x: width * 0.60, y: arrowY))
context.addLine(to: CGPoint(x: width * 0.57, y: arrowY - 6))
context.strokePath()

// The right-click → Open shortcut stopped working for unnotarised apps in
// macOS 15; Privacy & Security is now the only route, so that is what the
// window says.
draw("First launch: System Settings ▸ Privacy & Security ▸ Open Anyway", size: 9.5, weight: .regular, y: 54, alpha: 0.5)
draw("macOS 26 · no permissions needed", size: 9, weight: .regular, y: 30, alpha: 0.3)

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! data.write(to: URL(fileURLWithPath: output))
print("wrote \(output) (\(Int(pixels.width))×\(Int(pixels.height)))")
