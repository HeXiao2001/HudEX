import AppKit
import Foundation
import HudEXCore
import ServiceManagement
import SwiftUI

/// Launch at Login, backed by Apple's ServiceManagement framework.
///
/// `SMAppService.mainApp` is the supported API on macOS 13+; the status always
/// reflects what the system reports, never a cached boolean of our own.
@MainActor
final class LaunchAtLoginService: ObservableObject {
    static let shared = LaunchAtLoginService()

    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var requiresApproval: Bool = false
    @Published private(set) var lastError: String?

    private init() {
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval
        switch status {
        case .enabled:
            lastError = nil
        case .requiresApproval:
            lastError = "需要在“系统设置 › 通用 › 登录项”中允许 HudEX。"
        case .notRegistered, .notFound:
            lastError = nil
        @unknown default:
            lastError = nil
        }
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                    try SMAppService.mainApp.unregister()
                }
            }
            lastError = nil
        } catch {
            lastError = "设置开机启动失败：\(error.localizedDescription)"
            Log.app.error("SMAppService change failed: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    /// Opens the Login Items pane, for the `requiresApproval` case.
    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Opens files with whatever application the user has made the default.
@MainActor
enum ExternalOpenService {
    /// Opens `HudEX.md`. HudEX deliberately ships no editor: macOS decides.
    @discardableResult
    static func openFile(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        return NSWorkspace.shared.open(url)
    }

    static func openWebURL(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        NSWorkspace.shared.open(url)
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func openFolder(_ url: URL) {
        NSWorkspace.shared.open(url.deletingLastPathComponent())
    }
}

/// Opens the HudEX settings window.
///
/// HudEX hosts its own settings window instead of using SwiftUI's `Settings`
/// scene: the scene cannot be opened from AppKit code in an agent app (the
/// documented `SettingsLink` only works from inside SwiftUI), and keeping a
/// second scene alive makes SwiftUI rebuild the app main menu in a loop.
/// The window still uses native controls only.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        let window = ensureWindow()
        NSApp.activate(ignoringOtherApps: true)
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    private func ensureWindow() -> NSWindow {
        if let window { return window }
        let hosting = NSHostingView(rootView: SettingsView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("settings.window.title")
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setFrameAutosaveName("HudEXSettingsWindow")
        self.window = window
        return window
    }
}

@MainActor
enum SettingsOpener {
    static func open() {
        SettingsWindowController.shared.show()
    }
}
