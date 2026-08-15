import AppKit
import ApplicationServices
import DeskHUDCore
import ServiceManagement

struct HUDRuntimeStatus: Equatable {
    var lastReloadAt: String?
    var lastError: String?
    var watchDirectory: String?
    var accessibilityTrusted: Bool = false
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windowManager = HUDWindowManager()
    private let loader = HUDFileLoader()
    private var statusItem: NSStatusItem?
    private var currentConfig = HUDConfig()
    private var currentDocument = HUDDocument.empty
    private var runtimeStatus = HUDRuntimeStatus()
    private var settingsWindowController: SettingsWindowController?
    private var fileWatchers: [DispatchSourceFileSystemObject] = []
    private var reloadDebounceTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        requestAccessibilityTrustIfNeeded()
        registerRenderers()
        installMenuBarItem()
        installCLIListener()
        renderInitialHUD()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopFileWatchers()
        windowManager.closeAll()
    }

    private func registerRenderers() {
        let registry = HUDItemRendererRegistry.shared
        registry.register(TextItemRenderer())
        registry.register(MetricItemRenderer())
        registry.register(ProgressItemRenderer())
        registry.register(ListItemRenderer())
        registry.register(StatusItemRenderer())
        registry.register(AlertItemRenderer())
        registry.register(CountdownItemRenderer())
    }

    private func renderInitialHUD() {
        // 1. Always load bundled config for defaults.
        let bundledConfigURL = resourceURL(named: "config", extension: "json")
        let bundledConfig = bundledConfigURL.flatMap { try? loader.loadConfig(from: $0).get() } ?? HUDConfig()

        // 2. Use the watchDirectory from currentConfig if the user overrode it
        //    in Settings, otherwise from the bundled config file.
        let watchPath = currentConfig.watchDirectory?.isEmpty == false
            ? currentConfig.watchDirectory
            : bundledConfig.watchDirectory
        let watchDir: URL? = {
            guard let dir = watchPath, !dir.isEmpty else { return nil }
            let url = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }()

        // 3. Merge external config (if any) on top of bundled.  Missing fields
        //    keep their bundled values so incomplete external configs work.
        if let watchDir, let extURL = watchDir.appendingPathComponentIfExists("config.json") {
            if case .success(let extConfig) = loader.loadConfig(from: extURL) {
                currentConfig = extConfig
            } else {
                currentConfig = bundledConfig
            }
        } else {
            currentConfig = bundledConfig
        }
        // Preserve the active watchDirectory
        currentConfig.watchDirectory = watchPath

        // 4. Load HUD from watch dir or bundled.
        let hudURL: URL? = {
            if let watchDir { return watchDir.appendingPathComponentIfExists("hud.json") }
            return resourceURL(named: "hud", extension: "json")
        }()
        var document = hudURL.flatMap { try? loader.loadHUD(from: $0).get() } ?? .empty

        // 5. Per-slot files and calendar.
        document = mergeSlotFiles(into: document, baseDir: watchDir)
        document = mergeAgendaSources(into: document)

        currentDocument = document
        applyConfigAndDocument()
        installFileWatchers(watchDir: watchDir)
    }

    /// For each slot, if a file named `hud_{slot.id}.json` exists, load it and
    /// replace that slot's sections/items.  Slot files use the lightweight
    /// `HUDSlotContent` format — no need for the full HUDDocument envelope.
    private func mergeSlotFiles(into document: HUDDocument, baseDir: URL?) -> HUDDocument {
        var doc = document
        for i in doc.slots.indices {
            let slot = doc.slots[i]
            let slotURL: URL? = {
                if let base = baseDir {
                    let url = base.appendingPathComponent("hud_\(slot.id).json")
                    return FileManager.default.fileExists(atPath: url.path) ? url : nil
                }
                return resourceURL(named: "hud_\(slot.id)", extension: "json")
            }()
            guard let slotURL,
                  case .success(let content) = loader.loadSlotContent(from: slotURL)
            else { continue }
            doc.slots[i].sections = content.sections
            doc.slots[i].items = content.items
        }
        return doc
    }

    /// Enrich the left (agenda) slot with calendar events and reminders.
    /// External file content is handled by `watchDirectory` — no separate path needed.
    private func mergeAgendaSources(into document: HUDDocument) -> HUDDocument {
        var doc = document
        guard let leftIndex = doc.slots.firstIndex(where: { $0.anchor == .dockLeft })
        else { return doc }

        var items = doc.slots[leftIndex].resolvedSections.flatMap { $0.items }

        // Calendar
        if currentConfig.calendarEvents {
            items.append(contentsOf: CalendarReader.fetch())
        }

        // Sort: by time first (schedule + todos interleaved chronologically),
        // then incomplete before done.
        items.sort { a, b in
            let aTime = a.label ?? a.time ?? ""
            let bTime = b.label ?? b.time ?? ""
            // Items with time come before items without
            let aHasTime = !aTime.isEmpty
            let bHasTime = !bTime.isEmpty
            if aHasTime != bHasTime { return aHasTime }
            // Both have time → chronological
            if aHasTime && bHasTime && aTime != bTime { return aTime < bTime }
            // Same time or both no time → incomplete first
            let order: [String] = ["running", "active", "working", "thinking", "pending", "todo", "done"]
            let aIdx = order.firstIndex(of: a.state?.lowercased() ?? "") ?? order.count
            let bIdx = order.firstIndex(of: b.state?.lowercased() ?? "") ?? order.count
            return aIdx < bIdx
        }

        doc.slots[leftIndex].sections = [
            HUDSection(id: "agenda", title: nil, items: items)
        ]
        doc.slots[leftIndex].items = items
        return doc
    }

    private func applyConfigAndDocument() {
        windowManager.show(document: currentDocument, config: currentConfig)
        runtimeStatus.lastReloadAt = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        runtimeStatus.watchDirectory = currentConfig.watchDirectory
        runtimeStatus.accessibilityTrusted = AXIsProcessTrusted()
        settingsWindowController?.updateConfig(currentConfig, status: runtimeStatus)
        updateMenuBarVisibility()
        setLoginItem(enabled: currentConfig.launchAtLogin)
        saveSettings()
    }

    // MARK: - Settings persistence

    private func configFileURL() -> URL? {
        if let dir = currentConfig.watchDirectory, !dir.isEmpty {
            let url = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
            if FileManager.default.fileExists(atPath: url.path) {
                return url.appendingPathComponent("config.json")
            }
        }
        return resourceURL(named: "config", extension: "json")
    }

    private func saveSettings() {
        guard let url = configFileURL() else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(currentConfig) {
            try? data.write(to: url)
        }
    }

    // MARK: - Login item

    private func setLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            runtimeStatus.lastError = "Login item: \(error.localizedDescription)"
        }
    }

    // MARK: - CLI IPC

    private func installCLIListener() {
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleCLIReload),
            name: NSNotification.Name("deskhudctl.reload"),
            object: nil
        )
    }

    @objc private func handleCLIReload() {
        renderInitialHUD()
    }

    private func resourceURL(named name: String, extension fileExtension: String) -> URL? {
        // 1. Check bundle Resources
        if let bundled = Bundle.main.url(forResource: name, withExtension: fileExtension, subdirectory: "Examples") {
            return bundled
        }
        // 2. Check current directory (for development)
        let cwdFallback = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Examples")
            .appendingPathComponent("\(name).\(fileExtension)")
        if FileManager.default.fileExists(atPath: cwdFallback.path) { return cwdFallback }
        // 3. Check next to executable (for app bundles where cwd is /)
        let exeDir = Bundle.main.bundleURL
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources").appendingPathComponent("Examples")
            .appendingPathComponent("\(name).\(fileExtension)")
        if FileManager.default.fileExists(atPath: exeDir.path) { return exeDir }
        return nil
    }

    // MARK: - Menu bar

    private func installMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let image = Bundle.main.image(forResource: "DockCueMenuTemplate") {
                image.isTemplate = true
                button.image = image
            } else {
                button.image = NSImage(systemSymbolName: "rectangle.split.2x2",
                                        accessibilityDescription: "DockCue")
                button.image?.isTemplate = true
            }
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings...",
                                 action: #selector(openSettings),
                                 keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Reload", action: #selector(reloadHUD), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
        updateMenuBarVisibility()
    }

    private func updateMenuBarVisibility() {
        statusItem?.isVisible = !currentConfig.hideMenuBar
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(config: currentConfig, status: runtimeStatus)
            settingsWindowController?.onConfigChanged = { [weak self] newConfig in
                Task { @MainActor [weak self] in
                    let dirChanged = newConfig.watchDirectory != self?.currentConfig.watchDirectory
                    self?.currentConfig = newConfig
                    if dirChanged {
                        // Reload files from the new directory
                        self?.renderInitialHUD()
                    } else {
                        self?.windowManager.reconfigure(config: newConfig)
                    }
                }
            }
        }
        settingsWindowController?.updateConfig(currentConfig)
        settingsWindowController?.show()
    }

    // MARK: - File watcher

    private func installFileWatchers(watchDir: URL?) {
        stopFileWatchers()
        let dir = watchDir ?? resourceURL(named: "config", extension: "json")?.deletingLastPathComponent()
        guard let dir else { return }

        let watchedFiles = ["hud.json", "hud_leftDock.json", "hud_rightDock.json", "config.json"]
        for fileName in watchedFiles {
            let fileURL = dir.appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }

            let fd = open(fileURL.path, O_EVTONLY)
            guard fd >= 0 else { continue }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                self?.scheduleDebouncedReload()
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()
            fileWatchers.append(source)
        }
    }

    private func scheduleDebouncedReload() {
        reloadDebounceTimer?.invalidate()
        reloadDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.renderInitialHUD()
            }
        }
    }

    private func stopFileWatchers() {
        reloadDebounceTimer?.invalidate()
        reloadDebounceTimer = nil
        for source in fileWatchers {
            source.cancel()
        }
        fileWatchers.removeAll()
    }

    // MARK: - Accessibility

    private func requestAccessibilityTrustIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc private func reloadHUD() {
        renderInitialHUD()
    }

    @objc private func checkForUpdates() {
        NSWorkspace.shared.open(URL(string: "https://github.com/HeXiao2001/DeskHUD/releases")!)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

}

private extension URL {
    func appendingPathComponentIfExists(_ name: String) -> URL? {
        let url = appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
