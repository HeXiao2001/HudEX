import HudEXCore
import SwiftUI

/// Layout settings.
///
/// HudEX reads the Dock's edge and thickness from the system, but it does not
/// watch the Dock continuously: the position is detected at launch and when the
/// system reports a screen change. Everything a user might want to pin down
/// (tag size, how many tags, where they start) can be set here instead.
struct LayoutSettingsView: View {
    @ObservedObject private var preferences = Preferences.shared
    @ObservedObject private var controller = HudEXController.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("Dock 位置") { value(controller.geometry.edgeName) }
                LabeledContent("Dock 厚度") { value("\(controller.geometry.thickness) pt") }
                LabeledContent("Dock 占用范围") {
                    value("\(controller.geometry.occupiedStart)–\(controller.geometry.occupiedEnd) pt")
                }
                LabeledContent("检测来源") { value(controller.geometry.sourceName) }
                LabeledContent("显示器") { value(controller.geometry.screenName) }
            } header: {
                Text("Dock 几何")
            } footer: {
                Text("HudEX 不修改 Dock、不注入 Dock，只使用 Dock 没有占用的边缘空间。位置在启动时和系统报告屏幕变化时重新检测，不需要任何权限。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("主位置") {
                    value("\(controller.geometry.primaryRange)・可放 \(controller.geometry.primaryCapacity) 个")
                }
                LabeledContent("溢出位置") {
                    value("\(controller.geometry.secondaryRange)・可放 \(controller.geometry.secondaryCapacity) 个")
                }
                if controller.overflowCount > 0 {
                    Text("有 \(controller.overflowCount) 个项目没有显示。可以调小标签、放宽数量上限，或在下面手动修正 Dock 占用范围。")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("标签位置")
            } footer: {
                Text("左/右 Dock：主位置在下方、向上排列，放满后从上方往下排列。下方 Dock：主位置在左侧、向右排列，放满后从右侧往左排列。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                slider(
                    title: "标签宽度（向屏幕内延伸）",
                    value: $preferences.tabProtrusion,
                    range: 0...56,
                    step: 1,
                    defaultValue: 0,
                    format: { $0 <= 0 ? "自动（跟随 Dock 厚度 \(controller.geometry.thickness) pt）" : "\(Int($0)) pt" }
                )
                slider(
                    title: "标签高度（沿屏幕边缘）",
                    value: $preferences.tabLength,
                    range: 0...48,
                    step: 1,
                    defaultValue: 0,
                    format: { $0 <= 0 ? "自动（按字号）" : "\(Int($0)) pt" }
                )
                slider(
                    title: "标签字号",
                    value: $preferences.fontSize,
                    range: 0...12,
                    step: 0.5,
                    defaultValue: 0,
                    format: { $0 <= 0 ? "自动（9–12 pt）" : String(format: "%.1f pt", $0) }
                )
                HStack {
                    Button("恢复自动尺寸") { preferences.resetTagSize() }
                }
            } header: {
                Text("标签尺寸")
            } footer: {
                Text("Dock 在左侧或右侧时，“宽度”是标签伸进屏幕的厚度，“高度”是它沿屏幕边缘的长度；Dock 在下方时两者互换。标签永远不会超过 Dock 的厚度。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("最多显示标签数")
                    Spacer()
                    Stepper(value: $preferences.maxTags, in: 0...20) {
                        Text(preferences.maxTags == 0 ? "不限" : "\(preferences.maxTags) 个")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                HStack {
                    Text("每个位置最多显示")
                    Spacer()
                    Stepper(value: $preferences.maxTagsPerSlot, in: 0...10) {
                        Text(preferences.maxTagsPerSlot == 0 ? "不限" : "\(preferences.maxTagsPerSlot) 个")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("数量")
            } footer: {
                Text("超出的项目不会显示，也不会挤压标签：它们只是留给菜单栏和“完整窗口”去看。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                slider(
                    title: "与 Dock 的间距",
                    value: $preferences.edgeGap,
                    range: 4...28,
                    step: 1,
                    defaultValue: 12,
                    format: { "\(Int($0)) pt" }
                )
                slider(
                    title: "与屏幕转角的留白",
                    value: $preferences.cornerInset,
                    range: 0...24,
                    step: 1,
                    defaultValue: 8,
                    format: { "\(Int($0)) pt" }
                )
            } header: {
                Text("间距")
            }

            Section {
                slider(
                    title: "Dock 厚度（0 = 自动）",
                    value: $preferences.dockThicknessOverride,
                    range: 0...120,
                    step: 1,
                    defaultValue: 0,
                    format: { $0 <= 0 ? "自动（当前 \(controller.geometry.thickness) pt）" : "\(Int($0)) pt" }
                )
                slider(
                    title: "Dock 占用长度（0 = 自动）",
                    value: $preferences.dockLengthOverride,
                    range: 0...1200,
                    step: 10,
                    defaultValue: 0,
                    format: { value in
                        guard value > 0 else {
                            let length = controller.geometry.occupiedEnd - controller.geometry.occupiedStart
                            return "自动（当前 \(length) pt）"
                        }
                        return "\(Int(value)) pt"
                    }
                )
                HStack {
                    Button("恢复自动") { preferences.resetDockCalibration() }
                    Button("重新检测 Dock") { controller.resetDockGeometryCache() }
                }
            } header: {
                Text("手动校准")
            } footer: {
                Text("macOS 26 起，Dock 自己的窗口覆盖整个屏幕，公开 API 无法量出 Dock 的长度，HudEX 因此按偏好设置估算并且偏保守。如果标签和 Dock 有重叠，把占用长度调大即可。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func value(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary)
    }

    private func slider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        defaultValue: Double,
        format: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value.wrappedValue))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack(spacing: 10) {
                Slider(value: value, in: range, step: step)
                Button("默认") { value.wrappedValue = defaultValue }
                    .controlSize(.small)
            }
        }
    }
}

struct AppearanceSettingsView: View {
    @ObservedObject private var preferences = Preferences.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("更新时间") {
                    Text(preferences.showUpdatedTime ? "显示" : "隐藏")
                        .foregroundStyle(.secondary)
                }
                Toggle("在简介窗口显示“更新时间”", isOn: $preferences.showUpdatedTime)
            } header: {
                Text("简介窗口")
            } footer: {
                Text("标签只显示短名，颜色本身表示状态；鼠标悬停才会出现简介窗口。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                dayStepper(title: "最近更新（绿色）", value: $preferences.thresholdActive, range: 0...30)
                dayStepper(title: "需要关注（黄色）", value: $preferences.thresholdAttention, range: 1...60)
                dayStepper(title: "开始变旧（橙色）", value: $preferences.thresholdAging, range: 2...180)
            } header: {
                Text("颜色阈值")
            } footer: {
                Text("超过最后一个阈值就是灰色（长时间未更新）。状态为“暂停 / 归档 / 已完成”的项目固定使用蓝灰色。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(TagColorRole.allCases, id: \.self) { role in
                    HStack(spacing: 10) {
                        TagSwatch(role: role, label: sampleLabel(for: role))
                        Text(role.displayName)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            } header: {
                Text("颜色示例")
            } footer: {
                Text("颜色本身表示状态，标签上不会再画状态圆点。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func sampleLabel(for role: TagColorRole) -> String {
        switch role {
        case .active: return "GR"
        case .attention: return "OD"
        case .aging: return "ML"
        case .stale: return "PhD"
        case .paused: return "X"
        case .archived: return "✓"
        }
    }

    private func dayStepper(title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Stepper(value: value, in: range) {
                Text("\(value.wrappedValue) 天")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

/// A miniature tag, drawn with exactly the same colour rules as the real tabs.
struct TagSwatch: View {
    let role: TagColorRole
    let label: String

    var body: some View {
        let background = EdgeTagStyle.backgroundColor(for: role)
        let foreground = EdgeTagStyle.textColor(on: background)
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(nsColor: foreground))
            .lineLimit(1)
            .frame(width: 48, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(nsColor: background))
            )
    }
}
