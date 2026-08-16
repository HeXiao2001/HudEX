import AppKit
import DeskHUDCore
import SwiftUI

struct SettingsView: View {
    /// Working copy the user edits; changes propagate via `onConfigChanged`.
    @State private var config: HUDConfig
    /// Config pushed from the app (file reloads, external updates).
    private let incomingConfig: HUDConfig
    let status: HUDRuntimeStatus
    let onConfigChanged: (HUDConfig) -> Void

    @State private var selectedPage: Page = .layout

    enum Page: String, CaseIterable, Identifiable {
        case layout, appearance, content, advanced
        var id: String { rawValue }

        var label: String {
            switch self {
            case .layout: return tr("Layout")
            case .appearance: return tr("Appearance")
            case .content: return tr("Content")
            case .advanced: return tr("Advanced")
            }
        }

        var icon: String {
            switch self {
            case .layout: return "rectangle.2.group"
            case .appearance: return "paintbrush"
            case .content: return "list.bullet.rectangle"
            case .advanced: return "gearshape"
            }
        }
    }

    init(config: HUDConfig, status: HUDRuntimeStatus = HUDRuntimeStatus(), onConfigChanged: @escaping (HUDConfig) -> Void) {
        _config = State(initialValue: config)
        self.incomingConfig = config
        self.status = status
        self.onConfigChanged = onConfigChanged
    }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selectedPage) {
                ForEach(Page.allCases) { page in
                    Label(page.label, systemImage: page.icon)
                        .tag(page)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 180)

            Divider()

            Group {
                switch selectedPage {
                case .layout: LayoutPane(config: $config, status: status)
                case .appearance: AppearancePane(config: $config)
                case .content: ContentPane(config: $config)
                case .advanced: AdvancedPane(config: $config, status: status)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 680, minHeight: 470)
        .onChange(of: incomingConfig) { _, newValue in
            // External refresh (file reload); never clobber identical values.
            if newValue != config { config = newValue }
        }
        .onChange(of: config) { _, newValue in
            onConfigChanged(newValue)
        }
    }
}

// MARK: - Layout

private struct LayoutPane: View {
    @Binding var config: HUDConfig
    let status: HUDRuntimeStatus

    var body: some View {
        Form {
            Section {
                DockLayoutPreview(config: config)
                    .frame(height: 240)
            } header: {
                Text(tr("Panel Placement"))
            } footer: {
                Text(tr("Live preview of where the panels sit next to your Dock. Changes apply instantly."))
            }

            Section {
                Toggle(tr("Now Queue Panel"), isOn: $config.leftPanelEnabled)
                    .help(tr("Now Queue Panel"))
                Text(tr("Upcoming agenda: left of the bottom Dock, above a side Dock."))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(tr("Context Card Panel"), isOn: $config.rightPanelEnabled)
                Text(tr("Why the work matters: right of the bottom Dock, below a side Dock."))
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text(tr("Panels"))
            }

            Section {
                LabeledContent(tr("Extra panel width")) {
                    Stepper("\(Int(config.sidePanelExtraWidth))pt",
                            value: $config.sidePanelExtraWidth, in: 0 ... 40, step: 2)
                }
            } header: {
                Text(tr("Side Dock"))
            } footer: {
                Text(tr("Side-Dock panels are slightly wider than the Dock itself; adjust the extra margin."))
            }

            Section {
                Picker(tr("Display Target"), selection: $config.displays) {
                    Text(tr("All Displays")).tag(DisplayMode.all)
                    Text(tr("Primary Display")).tag(DisplayMode.primary)
                    Text(tr("Mouse Display")).tag(DisplayMode.mouse)
                    Text(tr("Fixed Display")).tag(DisplayMode.fixed)
                }
                if config.displays == .fixed {
                    Picker(tr("Fixed Display"), selection: Binding(
                        get: { config.fixedDisplayID ?? 0 },
                        set: { config.fixedDisplayID = $0 }
                    )) {
                        ForEach(NSScreen.screens, id: \.hash) { screen in
                            Text(HUDDisplayResolver.displayName(for: screen))
                                .tag(screenDisplayID(screen))
                        }
                    }
                }
                Picker(tr("Full-Screen Behavior"), selection: $config.fullscreenMode) {
                    Text(tr("Show in Full-Screen Spaces")).tag(FullscreenMode.overlay)
                    Text(tr("Desktop Spaces Only")).tag(FullscreenMode.desktopOnly)
                }
                if let err = status.lastError, config.displays == .fixed {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text(tr("Display"))
            }
        }
        .formStyle(.grouped)
        .padding()
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
            Section {
                Picker(tr("Background"), selection: $config.backgroundStyle) {
                    Text(tr("Liquid Glass (Dock-like)")).tag(DeskHUDCore.BackgroundStyle.glass)
                    Text(tr("Clear")).tag(DeskHUDCore.BackgroundStyle.clear)
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text(tr("Background"))
            }

            Section {
                Picker(tr("Side Dock Text"), selection: $config.sideDockTextMode) {
                    Text(tr("Vertical (CJK-friendly)")).tag(SideDockTextMode.vertical)
                    Text(tr("Rotated 90°")).tag(SideDockTextMode.rotated)
                }
                .pickerStyle(.radioGroup)
                if config.sideDockTextMode == .rotated {
                    Label(
                        tr("Rotated text reads sideways — fine for English, awkward for Chinese. Only applies to narrow side Docks."),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
                Label(
                    tr("Tip: vertical side-Dock panels read best with Chinese content — Latin runs rotate 90° automatically. For English-heavy content, prefer the Dock at the bottom or translate to Chinese."),
                    systemImage: "lightbulb"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text(tr("Side Dock Text"))
            }

            Section {
                LabeledContent(tr("Font Size")) {
                    Stepper("\(Int(config.window.fontSize))pt",
                            value: $config.window.fontSize, in: 9 ... 18, step: 1)
                }
                Picker(tr("Density"), selection: $config.window.contentDensity) {
                    Text(tr("Compact")).tag(ContentDensity.compact)
                    Text(tr("Comfortable")).tag(ContentDensity.comfortable)
                    Text(tr("Spacious")).tag(ContentDensity.spacious)
                }
                Picker(tr("Effect"), selection: $config.effectProfile) {
                    Text(tr("Low")).tag(EffectProfile.low)
                    Text(tr("Medium")).tag(EffectProfile.medium)
                    Text(tr("High")).tag(EffectProfile.high)
                }
            } header: {
                Text(tr("Typography"))
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Content

private struct ContentPane: View {
    @Binding var config: HUDConfig

    var body: some View {
        Form {
            Section {
                Picker(tr("Now Queue"), selection: $config.window.leftPresentation) {
                    Text(tr("Pager Rail")).tag(HUDPresentation.pagerRail)
                    Text(tr("Stack")).tag(HUDPresentation.stack)
                    Text(tr("Minimal")).tag(HUDPresentation.minimal)
                }
                Picker(tr("Context Card"), selection: $config.window.rightPresentation) {
                    Text(tr("Stack")).tag(HUDPresentation.stack)
                    Text(tr("Pager Rail")).tag(HUDPresentation.pagerRail)
                    Text(tr("Minimal")).tag(HUDPresentation.minimal)
                }
                LabeledContent(tr("Scroll Speed")) {
                    Stepper("\(Int(config.window.scrollIntervalSeconds))s",
                            value: $config.window.scrollIntervalSeconds, in: 2 ... 15, step: 1)
                }
                LabeledContent(tr("Max Lines")) {
                    Stepper("\(config.window.maxLines)",
                            value: Binding(get: { Double(config.window.maxLines) },
                                           set: { config.window.maxLines = Int($0) }),
                            in: 1 ... 6, step: 1)
                }
            } header: {
                Text(tr("Presentation"))
            }

            Section {
                Toggle(tr("Calendar"), isOn: $config.calendarEvents)
                Text(tr("Show calendar events and reminders in the Now Queue."))
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text(tr("Calendar"))
            }

            Section {
                LabeledContent(tr("Watch Directory")) {
                    HStack(spacing: 4) {
                        TextField("path", text: Binding(
                            get: { config.watchDirectory ?? "" },
                            set: { config.watchDirectory = $0.isEmpty ? nil : $0 }))
                            .frame(minWidth: 200)
                        Button(tr("Choose…")) { browseWatchDir() }
                    }
                }
            } header: {
                Text(tr("Data Source"))
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func browseWatchDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.prompt = tr("Choose…")
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
            Section {
                Toggle(tr("Launch at Login"), isOn: $config.launchAtLogin)
                Toggle(tr("Hide Menu Bar Item"), isOn: $config.hideMenuBar)
                Toggle(tr("Debug Logging"), isOn: $config.debugLogging)
            } header: {
                Text(tr("Startup"))
            }

            Section {
                LabeledContent(tr("Width (0 = auto)")) {
                    TextField("", value: $config.window.width, format: .number).frame(width: 70)
                    Stepper("", value: $config.window.width, in: 0 ... 600, step: 4)
                }
                LabeledContent(tr("Height")) {
                    TextField("", value: $config.window.height, format: .number).frame(width: 70)
                    Stepper("", value: $config.window.height, in: 40 ... 200, step: 2)
                }
                LabeledContent(tr("Margin")) {
                    TextField("", value: $config.window.margin, format: .number).frame(width: 70)
                    Stepper("", value: $config.window.margin, in: 2 ... 40, step: 2)
                }
            } header: {
                Text(tr("Bottom-Dock Panel Size"))
            } footer: {
                Text(tr("Applies to bottom Docks; side-Dock panels size themselves automatically."))
            }

            Section {
                HStack {
                    Text(tr("Status"))
                    Text(status.lastError == nil ? tr("OK") : tr("Error"))
                        .foregroundStyle(status.lastError == nil ? Color.green : Color.red)
                }
                if let err = status.lastError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                if let dir = status.watchDirectory {
                    Text("\(tr("Watch:")) \(dir)").font(.caption).foregroundStyle(.secondary)
                }
                if let time = status.lastReloadAt {
                    Text("\(tr("Reloaded:")) \(time)").font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text(tr("Diagnostics"))
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
