import AppKit
import DeskHUDCore
import SwiftUI

struct SettingsView: View {
    @State private var config: HUDConfig
    let status: HUDRuntimeStatus
    let onConfigChanged: (HUDConfig) -> Void

    init(config: HUDConfig, status: HUDRuntimeStatus = HUDRuntimeStatus(), onConfigChanged: @escaping (HUDConfig) -> Void) {
        _config = State(initialValue: config)
        self.status = status
        self.onConfigChanged = onConfigChanged
    }

    var body: some View {
        TabView {
            DisplayPane(config: $config, status: status)
                .tabItem { Label("Display", systemImage: "display") }
                .frame(width: 500, height: 360)
            AppearancePane(config: $config)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
                .frame(width: 500, height: 360)
            ContentPane(config: $config)
                .tabItem { Label("Content", systemImage: "list.bullet.rectangle") }
                .frame(width: 500, height: 360)
            AdvancedPane(config: $config, status: status)
                .tabItem { Label("Advanced", systemImage: "gearshape") }
                .frame(width: 500, height: 360)
        }
        .frame(width: 540, height: 420)
        .padding(.top, 8)
        .scenePadding()
        .onChange(of: config) { _, newValue in
            onConfigChanged(newValue)
        }
    }
}

// MARK: - Display

private struct DisplayPane: View {
    @Binding var config: HUDConfig
    let status: HUDRuntimeStatus

    var body: some View {
        Form {
            Picker("Display Target:", selection: $config.displays) {
                Text("All Displays").tag(DisplayMode.all)
                Text("Primary Display").tag(DisplayMode.primary)
                Text("Mouse Display").tag(DisplayMode.mouse)
                Text("Fixed Display").tag(DisplayMode.fixed)
            }

            if config.displays == .fixed {
                Picker("Fixed Display:", selection: Binding(
                    get: { config.fixedDisplayID ?? 0 },
                    set: { config.fixedDisplayID = $0 }
                )) {
                    ForEach(NSScreen.screens, id: \.hash) { screen in
                        Text(HUDDisplayResolver.displayName(for: screen))
                            .tag(screenDisplayID(screen))
                    }
                }
            }

            Picker("Full-Screen:", selection: $config.fullscreenMode) {
                Text("Show in Full-Screen Spaces").tag(FullscreenMode.overlay)
                Text("Desktop Spaces Only").tag(FullscreenMode.desktopOnly)
            }

            if let err = status.lastError, config.displays == .fixed {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func screenDisplayID(_ screen: NSScreen) -> UInt32 {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0
    }
}

// MARK: - Appearance

private struct AppearancePane: View {
    @Binding var config: HUDConfig

    var body: some View {
        Form {
            Picker("Background:", selection: $config.backgroundStyle) {
                Text("Liquid Glass (Dock-like)").tag(DeskHUDCore.BackgroundStyle.glass)
                Text("Clear").tag(DeskHUDCore.BackgroundStyle.clear)
            }

            Picker("Effect:", selection: $config.effectProfile) {
                Text("Low").tag(EffectProfile.low)
                Text("Medium").tag(EffectProfile.medium)
                Text("High").tag(EffectProfile.high)
            }

            Picker("Density:", selection: $config.window.contentDensity) {
                Text("Compact").tag(ContentDensity.compact)
                Text("Comfortable").tag(ContentDensity.comfortable)
                Text("Spacious").tag(ContentDensity.spacious)
            }

            LabeledContent("Font Size:") {
                Stepper("\(Int(config.window.fontSize))pt",
                        value: $config.window.fontSize, in: 9 ... 18, step: 1)
            }
        }
    }
}

// MARK: - Content

private struct ContentPane: View {
    @Binding var config: HUDConfig

    var body: some View {
        Form {
            Picker("Left:", selection: $config.window.leftPresentation) {
                Text("Pager Rail").tag(HUDPresentation.pagerRail)
                Text("Stack").tag(HUDPresentation.stack)
                Text("Minimal").tag(HUDPresentation.minimal)
            }

            Picker("Right:", selection: $config.window.rightPresentation) {
                Text("Stack").tag(HUDPresentation.stack)
                Text("Pager Rail").tag(HUDPresentation.pagerRail)
                Text("Minimal").tag(HUDPresentation.minimal)
            }

            LabeledContent("Scroll speed:") {
                Stepper("\(Int(config.window.scrollIntervalSeconds))s",
                        value: $config.window.scrollIntervalSeconds, in: 2 ... 15, step: 1)
            }

            LabeledContent("Max Lines:") {
                Stepper("\(config.window.maxLines)",
                        value: Binding(get: { Double(config.window.maxLines) },
                                       set: { config.window.maxLines = Int($0) }),
                        in: 1 ... 6, step: 1)
            }

            Toggle("Calendar Events", isOn: $config.calendarEvents)

            LabeledContent("Watch Dir:") {
                HStack(spacing: 4) {
                    TextField("path", text: Binding(
                        get: { config.watchDirectory ?? "" },
                        set: { config.watchDirectory = $0.isEmpty ? nil : $0 }))
                    .frame(minWidth: 160)
                    Button("Choose...") { browseWatchDir() }
                }
            }
        }
    }

    private func browseWatchDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.prompt = "Select Watch Directory"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        config.watchDirectory = url.path
    }
}

// MARK: - Advanced

private struct AdvancedPane: View {
    @Binding var config: HUDConfig
    let status: HUDRuntimeStatus

    var body: some View {
        Form {
            Toggle("Launch at Login", isOn: $config.launchAtLogin)
            Toggle("Hide Menu Bar", isOn: $config.hideMenuBar)
            Toggle("Debug Logging", isOn: $config.debugLogging)

            LabeledContent("Width (0=auto):") {
                TextField("", value: $config.window.width, format: .number).frame(width: 70)
                Stepper("", value: $config.window.width, in: 0 ... 600, step: 4)
            }

            LabeledContent("Height:") {
                TextField("", value: $config.window.height, format: .number).frame(width: 70)
                Stepper("", value: $config.window.height, in: 40 ... 200, step: 2)
            }

            LabeledContent("Margin:") {
                TextField("", value: $config.window.margin, format: .number).frame(width: 70)
                Stepper("", value: $config.window.margin, in: 2 ... 40, step: 2)
            }

            Divider()

            Group {
                HStack {
                    Text("Status:")
                    Text(status.lastError == nil ? "OK" : "Error")
                        .foregroundStyle(status.lastError == nil ? Color.green : Color.red)
                }
                if let err = status.lastError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                if let dir = status.watchDirectory {
                    Text("Watch: \(dir)").font(.caption).foregroundStyle(.secondary)
                }
                if let time = status.lastReloadAt {
                    Text("Reloaded: \(time)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
