#!/usr/bin/env swift
// Counts the windows of the running HudEX (visible or not). Used by the smoke test.
import AppKit
import CoreGraphics

guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.hex.hudex").first else {
    print(0)
    exit(0)
}
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
let count = list.filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier }.count
print(count)
