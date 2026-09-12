import AppKit
import HudEXCore
import SwiftUI

/// Application entry point.
///
/// HudEX is a pure AppKit application that hosts SwiftUI *views* inside its
/// windows. It deliberately has no SwiftUI `App`/`Scene`: an agent app built
/// from scenes (MenuBarExtra + Settings) makes SwiftUI rebuild the application
/// main menu on every graph change, which stalls the app and stops its windows
/// from following the Dock. The status item below replaces `MenuBarExtra` and
/// gives the same functionality with a native `NSMenu`.
@main
enum HudEXMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = HudEXController.shared
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Exactly one HudEX may run: two instances would each write their own
        // settings back into the same Markdown file and fight over it.
        if let other = Self.otherInstance() {
            Log.app.warning("another HudEX is already running (pid \(other.processIdentifier)); handing over")
            other.activate()
            NSApp.terminate(nil)
            return
        }

        // LSUIElement is set in Info.plist; this keeps the behaviour when the
        // binary is run directly from a terminal.
        NSApp.setActivationPolicy(.accessory)
        statusItem = StatusItemController(controller: controller)
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    /// Any other running copy of this bundle, if there is one.
    private static func otherInstance() -> NSRunningApplication? {
        let identifier = Bundle.main.bundleIdentifier ?? "dev.hex.hudex"
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication
            .runningApplications(withBundleIdentifier: identifier)
            .first { $0.processIdentifier != ownPID }
    }

    /// Launching HudEX again (Spotlight, Launchpad, Finder, `open`) while it is
    /// already running opens Settings. A menu-bar app has no window to raise, so
    /// without this the second launch would look like nothing happened.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        controller.openSettings()
        return true
    }
}

/// The optional menu bar icon.
///
/// A plain `NSStatusItem` with a native `NSMenu`. The menu's state is refreshed
/// only when it is about to open (`menuNeedsUpdate`), so an idle HudEX does no
/// work for it at all.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let controller: HudEXController
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    private enum Item {
        static let showTags = 1
        static let openMarkdown = 2
        static let reveal = 3
        static let reload = 4
        static let settings = 5
        static let launchAtLogin = 6
        static let showIcon = 7
        static let quit = 8
    }

    init(controller: HudEXController) {
        self.controller = controller
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureButton()
        configureMenu()
        updateVisibility()
        controller.preferencesBinding = self
    }

    /// Keeps the icon in sync with the preference without a scene graph.
    func updateVisibility() {
        statusItem.isVisible = controller.preferences.showMenuBarIcon
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "bookmark.fill", accessibilityDescription: "HudEX")
        image?.isTemplate = true          // monochrome, matches other menu bar items
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = "HudEX"
        statusItem.menu = menu
    }

    private func configureMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        addItem(title: L10n.t("diagnostics.title", HudEXController.version), action: nil, key: "", tag: 0)
        menu.addItem(.separator())
        addItem(title: L10n.t("menu.showTags"), action: #selector(toggleShowTags), key: "", tag: Item.showTags)
        addItem(title: L10n.t("menu.openMarkdown"), action: #selector(openMarkdown), key: "o", tag: Item.openMarkdown)
        addItem(title: L10n.t("menu.reveal"), action: #selector(revealMarkdown), key: "", tag: Item.reveal)
        addItem(title: L10n.t("menu.reload"), action: #selector(reload), key: "r", tag: Item.reload)
        addItem(title: L10n.t("menu.settings"), action: #selector(openSettings), key: ",", tag: Item.settings)
        menu.addItem(.separator())
        addItem(title: L10n.t("menu.launchAtLogin"), action: #selector(toggleLaunchAtLogin), key: "", tag: Item.launchAtLogin)
        addItem(title: L10n.t("menu.showMenuBarIcon"), action: #selector(toggleShowIcon), key: "", tag: Item.showIcon)
        menu.addItem(.separator())
        addItem(title: L10n.t("menu.quit"), action: #selector(quit), key: "q", tag: Item.quit)
    }

    /// Re-applies the localised titles.
    private func applyTitles() {
        let titles: [Int: String] = [
            Item.showTags: L10n.t("menu.showTags"),
            Item.openMarkdown: L10n.t("menu.openMarkdown"),
            Item.reveal: L10n.t("menu.reveal"),
            Item.reload: L10n.t("menu.reload"),
            Item.settings: L10n.t("menu.settings"),
            Item.launchAtLogin: L10n.t("menu.launchAtLogin"),
            Item.showIcon: L10n.t("menu.showMenuBarIcon"),
            Item.quit: L10n.t("menu.quit")
        ]
        for (tag, title) in titles {
            menu.item(withTag: tag)?.title = title
        }
    }

    private func addItem(title: String, action: Selector?, key: String, tag: Int) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = action == nil ? nil : self
        item.tag = tag
        item.state = .off
        if action == nil {
            item.isEnabled = false
        }
        menu.addItem(item)
    }

    // MARK: - Menu state

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Titles are re-applied on every open so a language change is picked up
        // without restarting the app.
        applyTitles()
        menu.item(withTag: Item.showTags)?.state = controller.preferences.showTags ? .on : .off
        menu.item(withTag: Item.showIcon)?.state = controller.preferences.showMenuBarIcon ? .on : .off
        menu.item(withTag: Item.launchAtLogin)?.state = controller.launchAtLogin.isEnabled ? .on : .off

        menu.item(withTag: 0)?.title = L10n.t("diagnostics.title", HudEXController.version)
    }

    // MARK: - Actions

    @objc private func toggleShowTags() {
        controller.preferences.showTags.toggle()
    }

    @objc private func openMarkdown() {
        controller.openMarkdownFile()
    }

    @objc private func revealMarkdown() {
        controller.revealInFinder()
    }

    @objc private func reload() {
        controller.reloadDocument()
    }

    @objc private func openSettings() {
        controller.openSettings()
    }

    @objc private func toggleLaunchAtLogin() {
        controller.launchAtLogin.setEnabled(!controller.launchAtLogin.isEnabled)
    }

    @objc private func toggleShowIcon() {
        let preferences = controller.preferences
        preferences.showMenuBarIcon.toggle()
        updateVisibility()
        if !preferences.showMenuBarIcon {
            // Tell the user how to get back in.
            controller.settingsWindow().show()
        }
    }

    @objc private func quit() {
        controller.quit()
    }
}
