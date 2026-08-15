import AppKit
import DeskHUDCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private var currentConfig: HUDConfig
    private var currentStatus: HUDRuntimeStatus
    var onConfigChanged: ((HUDConfig) -> Void)?

    init(config: HUDConfig, status: HUDRuntimeStatus = HUDRuntimeStatus()) {
        self.currentConfig = config
        self.currentStatus = status

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DockCue Settings"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        window.contentView = makeHostingView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeHostingView() -> NSHostingView<SettingsView> {
        let view = SettingsView(config: currentConfig, status: currentStatus) { [weak self] newConfig in
            self?.currentConfig = newConfig
            self?.onConfigChanged?(newConfig)
        }
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame.size = NSSize(width: 560, height: 480)
        return hostingView
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func updateConfig(_ newConfig: HUDConfig, status: HUDRuntimeStatus = HUDRuntimeStatus()) {
        currentConfig = newConfig
        currentStatus = status
        window?.contentView = makeHostingView()
    }
}
