#!/usr/bin/env swift
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let script = root.appendingPathComponent("script")
let iconset = script.appendingPathComponent("DockCue.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func png(_ image: NSImage, _ url: URL, _ px: Int) throws {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("bitmap") }
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}


func png(_ image: NSImage, _ url: URL, width: Int, height: Int) throws {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("bitmap") }
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func appIcon(_ px: Int) -> NSImage {
    let s = CGFloat(px)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    NSColor.clear.setFill(); NSRect(x: 0, y: 0, width: s, height: s).fill()

    let outer = NSRect(x: s * 0.018, y: s * 0.018, width: s * 0.964, height: s * 0.964)
    let bg = rounded(outer, s * 0.22)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.075, green: 0.085, blue: 0.108, alpha: 1),
        NSColor(calibratedRed: 0.035, green: 0.040, blue: 0.055, alpha: 1)
    ])!.draw(in: bg, angle: 90)
    NSColor(calibratedWhite: 1, alpha: 0.18).setStroke(); bg.lineWidth = max(1, s * 0.012); bg.stroke()
    NSColor(calibratedRed: 0.30, green: 0.95, blue: 1, alpha: 0.07).setStroke()
    let inner = rounded(outer.insetBy(dx: s * 0.045, dy: s * 0.045), s * 0.18)
    inner.lineWidth = max(1, s * 0.004); inner.stroke()

    let para = NSMutableParagraphStyle(); para.alignment = .center
    ("C" as NSString).draw(in: NSRect(x: s * 0.08, y: s * 0.34, width: s * 0.84, height: s * 0.38), withAttributes: [
        .font: NSFont.systemFont(ofSize: s * 0.34, weight: .heavy),
        .foregroundColor: NSColor(calibratedWhite: 0.94, alpha: 1),
        .paragraphStyle: para
    ])

    let barW = s * 0.245, barH = max(2, s * 0.043), y = s * 0.155, inset = s * 0.145
    NSColor(calibratedWhite: 1, alpha: 0.94).setFill()
    rounded(NSRect(x: inset, y: y, width: barW, height: barH), barH / 2).fill()
    rounded(NSRect(x: s - inset - barW, y: y, width: barW, height: barH), barH / 2).fill()
    NSColor(calibratedRed: 0.22, green: 0.95, blue: 1, alpha: 0.35).setFill()
    rounded(NSRect(x: s * 0.482, y: y + barH * 0.16, width: s * 0.036, height: barH * 0.68), s * 0.018).fill()
    image.unlockFocus()
    return image
}

func menuIcon(_ px: Int) -> NSImage {
    let s = CGFloat(px)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    NSColor.clear.setFill(); NSRect(x: 0, y: 0, width: s, height: s).fill()
    NSColor.black.setStroke(); NSColor.black.setFill()
    let center = rounded(NSRect(x: s * 0.30, y: s * 0.37, width: s * 0.40, height: s * 0.32), s * 0.075)
    center.lineWidth = max(1.4, s * 0.085); center.stroke()
    let h = max(1.8, s * 0.10), w = s * 0.30, y = s * 0.14
    rounded(NSRect(x: s * 0.10, y: y, width: w, height: h), h / 2).fill()
    rounded(NSRect(x: s * 0.60, y: y, width: w, height: h), h / 2).fill()
    image.unlockFocus(); image.isTemplate = true
    return image
}

func dmgBackground() -> NSImage {
    let size = NSSize(width: 640, height: 360)
    let image = NSImage(size: size)
    image.lockFocus()
    let rect = NSRect(origin: .zero, size: size)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.075, green: 0.083, blue: 0.105, alpha: 1),
        NSColor(calibratedRed: 0.035, green: 0.040, blue: 0.052, alpha: 1)
    ])!.draw(in: rect, angle: 90)
    NSColor(calibratedRed: 0.10, green: 0.86, blue: 0.90, alpha: 0.14).setFill()
    NSBezierPath(ovalIn: NSRect(x: 245, y: 145, width: 150, height: 150)).fill()
    let para = NSMutableParagraphStyle(); para.alignment = .center
    ("Drag DockCue to Applications" as NSString).draw(in: NSRect(x: 0, y: 286, width: 640, height: 30), withAttributes: [.font: NSFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: NSColor(calibratedWhite: 0.94, alpha: 1), .paragraphStyle: para])
    ("Quiet Dock-side cues for macOS" as NSString).draw(in: NSRect(x: 0, y: 262, width: 640, height: 22), withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor(calibratedWhite: 0.78, alpha: 0.72), .paragraphStyle: para])
    NSColor(calibratedWhite: 1, alpha: 0.44).setStroke()
    let arrow = NSBezierPath(); arrow.lineWidth = 3; arrow.lineCapStyle = .round
    arrow.move(to: NSPoint(x: 250, y: 142)); arrow.curve(to: NSPoint(x: 390, y: 142), controlPoint1: NSPoint(x: 292, y: 182), controlPoint2: NSPoint(x: 348, y: 182)); arrow.stroke()
    let head = NSBezierPath(); head.lineWidth = 3; head.lineCapStyle = .round
    head.move(to: NSPoint(x: 390, y: 142)); head.line(to: NSPoint(x: 370, y: 160)); head.move(to: NSPoint(x: 390, y: 142)); head.line(to: NSPoint(x: 370, y: 124)); head.stroke()
    image.unlockFocus()
    return image
}

let icons: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_64x64.png", 64), ("icon_64x64@2x.png", 128),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, px) in icons { try png(appIcon(px), iconset.appendingPathComponent(name), px) }
try png(menuIcon(18), script.appendingPathComponent("DockCueMenuTemplate.png"), 18)
try png(menuIcon(36), script.appendingPathComponent("DockCueMenuTemplate@2x.png"), 36)
try png(dmgBackground(), script.appendingPathComponent("dmg-background.png"), width: 640, height: 360)

let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", "-o", script.appendingPathComponent("DockCue.icns").path, iconset.path]
try p.run(); p.waitUntilExit()
if p.terminationStatus != 0 { fatalError("iconutil failed") }
print("Generated DockCue assets")
