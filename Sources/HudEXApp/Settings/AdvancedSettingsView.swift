import HudEXCore
import SwiftUI

struct AdvancedSettingsView: View {
    @ObservedObject private var preferences = Preferences.shared
    @ObservedObject private var controller = HudEXController.shared

    var body: some View {
        Form {
            Section {
                ScrollView {
                    Text(controller.diagnosticsText)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 168)

                HStack(spacing: 8) {
                    Button("重新载入") { controller.reloadDocument() }
                    Button("清空几何缓存") { controller.resetDockGeometryCache() }
                    Button("复制诊断信息") { copyDiagnostics() }
                }
            } header: {
                Text("诊断")
            }

            Section {
                LabeledContent("内存占用") {
                    Text(String(format: "%.1f MB", controller.performance.residentMegabytes))
                        .foregroundStyle(.secondary)
                }
                LabeledContent("累计 CPU 时间") {
                    Text(String(format: "%.2f 秒（平均 %.3f%%）",
                                controller.performance.cpuTimeSeconds,
                                controller.performance.averageCPUPercent))
                        .foregroundStyle(.secondary)
                }
                LabeledContent("线程数") {
                    Text("\(controller.performance.threadCount)").foregroundStyle(.secondary)
                }
            } header: {
                Text("资源占用")
            } footer: {
                Text("HudEX 空闲时不轮询、不联网、不写日志；这个数字来自系统对进程的统计。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("辅助功能权限") { Text("未使用").foregroundStyle(.secondary) }
                LabeledContent("屏幕录制权限") { Text("未使用").foregroundStyle(.secondary) }
                LabeledContent("网络访问") { Text("无").foregroundStyle(.secondary) }
            } header: {
                Text("权限与网络")
            } footer: {
                Text("HudEX 只使用公开的 AppKit API：Dock 位置与厚度来自系统保留区和 Dock 偏好设置，屏幕变化通过系统通知获知。标签尺寸与数量都可以在“布局”里手动设定，所以不需要任何 TCC 权限。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("工程结构") {
                    Text("HudEXCore（解析 / 布局 / 颜色）+ HudEXApp（窗口 / 设置 / 菜单栏）")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("日志") {
                    Text("os.Logger，分类：app / markdown / watcher / dock / layout / window")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("维护")
            }
        }
        .formStyle(.grouped)
    }

    private func copyDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(controller.diagnosticsText, forType: .string)
    }
}
