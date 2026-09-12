import HudEXCore
import SwiftUI

/// Native SwiftUI `Settings` scene: HudEX does not draw its own settings chrome.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("通用", systemImage: "gearshape") }
            SourceSettingsView()
                .tabItem { Label("数据源", systemImage: "doc.text") }
            LayoutSettingsView()
                .tabItem { Label("布局", systemImage: "rectangle.split.2x1") }
            AppearanceSettingsView()
                .tabItem { Label("外观", systemImage: "paintpalette") }
            AdvancedSettingsView()
                .tabItem { Label("高级", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 540)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject private var preferences = Preferences.shared
    @ObservedObject private var launchAtLogin = LaunchAtLoginService.shared
    @ObservedObject private var controller = HudEXController.shared

    var body: some View {
        Form {
            Section {
                Toggle("开机时自动启动", isOn: launchAtLoginBinding)

                if launchAtLogin.requiresApproval {
                    HStack(spacing: 8) {
                        Text("需要在系统设置中允许 HudEX。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("打开登录项设置") { launchAtLogin.openLoginItemsSettings() }
                    }
                }
                if let error = launchAtLogin.lastError, !launchAtLogin.requiresApproval {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("启动")
            }

            Section {
                Toggle("显示 HudEX 标签", isOn: $preferences.showTags)
                Toggle("显示 Menu Bar 图标", isOn: $preferences.showMenuBarIcon)
            } header: {
                Text("显示")
            } footer: {
                Text("即使关闭 Menu Bar 图标，也可以在任意标签上右键（或再次打开 HudEX）进入设置。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("版本") {
                    Text(HudEXController.version)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("数据源") {
                    Text(URL(fileURLWithPath: controller.documentSummary.path).lastPathComponent)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("项目数") {
                    Text("\(controller.documentSummary.projectCount)")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("关于")
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
}
