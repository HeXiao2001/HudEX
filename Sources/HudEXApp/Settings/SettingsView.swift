import HudEXCore
import SwiftUI

/// The settings window content. HudEX hosts it in its own window (see
/// `SettingsWindowController`) but the controls are all native SwiftUI.
struct SettingsView: View {
    /// Which pane to show first. `HUDEX_SETTINGS_TAB` (general/source/layout/
    /// appearance) selects it for development and documentation captures.
    @State private var selection: String = {
        switch ProcessInfo.processInfo.environment["HUDEX_SETTINGS_TAB"]?.lowercased() {
        case "source": return "source"
        case "layout": return "layout"
        case "appearance": return "appearance"
        default: return "general"
        }
    }()

    var body: some View {
        TabView(selection: $selection) {
            GeneralSettingsView()
                .tabItem { Label(L10n.t("settings.tab.general"), systemImage: "gearshape") }
                .tag("general")
            SourceSettingsView()
                .tabItem { Label(L10n.t("settings.tab.source"), systemImage: "doc.text") }
                .tag("source")
            LayoutSettingsView()
                .tabItem { Label(L10n.t("settings.tab.layout"), systemImage: "rectangle.split.2x1") }
                .tag("layout")
            AppearanceSettingsView()
                .tabItem { Label(L10n.t("settings.tab.appearance"), systemImage: "paintpalette") }
                .tag("appearance")
        }
        // Wide enough that macOS keeps the tabs visible as tabs instead of
        // collapsing them into an overflow menu.
        .frame(width: 620)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject private var preferences = Preferences.shared
    @ObservedObject private var launchAtLogin = LaunchAtLoginService.shared
    @ObservedObject private var controller = HudEXController.shared

    var body: some View {
        Form {
            Section {
                Toggle(L10n.t("general.launchAtLogin"), isOn: launchAtLoginBinding)

                if launchAtLogin.requiresApproval {
                    HStack(spacing: 8) {
                        Text(L10n.t("general.requiresApproval"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.t("general.openLoginItems")) { launchAtLogin.openLoginItemsSettings() }
                    }
                }
                if let error = launchAtLogin.lastError, !launchAtLogin.requiresApproval {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
            } header: {
                Text(L10n.t("general.section.startup"))
            }

            Section {
                Toggle(L10n.t("general.showTags"), isOn: $preferences.showTags)
                Toggle(L10n.t("general.showMenuBarIcon"), isOn: $preferences.showMenuBarIcon)
            } header: {
                Text(L10n.t("general.section.visibility"))
            } footer: {
                Text(L10n.t("general.menuBarFooter"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker(L10n.t("general.language"), selection: $preferences.language) {
                    Text(L10n.t("general.language.system")).tag("")
                    Text("English").tag("en")
                    Text("简体中文").tag("zh-Hans")
                }
            } header: {
                Text(L10n.t("general.section.language"))
            } footer: {
                Text(L10n.t("general.language.footer"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent(L10n.t("general.version")) { value(HudEXController.version) }
                LabeledContent(L10n.t("general.source")) {
                    value(URL(fileURLWithPath: controller.documentSummary.path).lastPathComponent)
                }
                LabeledContent(L10n.t("general.projectCount")) {
                    value("\(controller.documentSummary.projectCount)")
                }
            } header: {
                Text(L10n.t("general.section.about"))
            }
        }
        .formStyle(.grouped)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { launchAtLogin.setEnabled($0) }
        )
    }

    private func value(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary)
    }
}
