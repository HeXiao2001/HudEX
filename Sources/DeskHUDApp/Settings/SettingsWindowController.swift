import AppKit
import DeskHUDCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private var currentConfig: HUDConfig
    private var currentStatus: HUDRuntimeStatus
    private var hostingView: NSHostingView<SettingsView>?
    var onConfigChanged: ((HUDConfig) -> Void)?

    init(config: HUDConfig, status: HUDRuntimeStatus = HUDRuntimeStatus()) {
        self.currentConfig = config
        self.currentStatus = status

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = tr("DockCue Settings")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 680, height: 470)
        window.center()

        super.init(window: window)

        let hosting = makeHostingView()
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        hostingView = hosting
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeHostingView() -> NSHostingView<SettingsView> {
        let view = SettingsView(config: currentConfig, status: currentStatus) { [weak self] newConfig in
            self?.currentConfig = newConfig
            self?.onConfigChanged?(newConfig)
        }
        return NSHostingView(rootView: view)
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Push new config/status into the existing SwiftUI tree (keeps view
    /// state such as the selected sidebar page — no full rebuild).
    func updateConfig(_ newConfig: HUDConfig, status: HUDRuntimeStatus = HUDRuntimeStatus()) {
        currentConfig = newConfig
        currentStatus = status
        hostingView?.rootView = SettingsView(config: newConfig, status: status) { [weak self] changed in
            self?.currentConfig = changed
            self?.onConfigChanged?(changed)
        }
    }
}
