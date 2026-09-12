import HudEXCore
import SwiftUI

struct AppearanceSettingsView: View {
    @ObservedObject private var preferences = Preferences.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Form {
            styleSection

            Section {
                Toggle(L10n.t("appearance.showUpdatedTime"), isOn: $preferences.showUpdatedTime)
            } header: {
                Text(L10n.t("appearance.section.preview"))
            } footer: {
                Text(L10n.t("appearance.preview.footer"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(L10n.t("appearance.stack.enabled"), isOn: $preferences.stackEnabled)
                slider(
                    title: L10n.t("appearance.stack.overlap"),
                    value: $preferences.stackOverlap,
                    range: 0...0.8,
                    step: 0.02,
                    defaultValue: 0.34,
                    format: { String(format: "%.0f%%", $0 * 100) }
                )
                slider(
                    title: L10n.t("appearance.stack.rotation"),
                    value: $preferences.stackRotation,
                    range: -20...20,
                    step: 1,
                    defaultValue: -5,
                    format: { String(format: "%.0f°", $0) }
                )
                slider(
                    title: L10n.t("appearance.stack.stagger"),
                    value: $preferences.stackStagger,
                    range: 0...12,
                    step: 0.5,
                    defaultValue: 2.5,
                    format: { String(format: "%.1f pt", $0) }
                )
            } header: {
                Text(L10n.t("appearance.section.stack"))
            } footer: {
                Text(L10n.t("appearance.stack.footer"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                dayStepper(
                    title: L10n.t("appearance.color.active"),
                    value: $preferences.thresholdActive,
                    range: 0...60
                )
                dayStepper(
                    title: L10n.t("appearance.color.attention"),
                    value: $preferences.thresholdAttention,
                    range: 1...120
                )
                dayStepper(
                    title: L10n.t("appearance.color.aging"),
                    value: $preferences.thresholdAging,
                    range: 2...365
                )
            } header: {
                Text(L10n.t("appearance.section.thresholds"))
            } footer: {
                Text(L10n.t("appearance.thresholds.footer"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(TagColorRole.allCases, id: \.self) { role in
                    HStack(spacing: 10) {
                        TagSwatch(role: role, label: sampleLabel(for: role), isDark: colorScheme == .dark)
                        Text(role.displayName).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            } header: {
                Text(L10n.t("appearance.section.legend"))
            } footer: {
                Text(L10n.t("appearance.legend.footer"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// The look of the tags and of the hover card.
    private var styleSection: some View {
        Section {
            Picker(L10n.t("appearance.style"), selection: $preferences.appearanceStyle) {
                ForEach(AppearanceStyle.allCases, id: \.self) { style in
                    Text(L10n.t(style.displayNameKey)).tag(style)
                }
            }
            .pickerStyle(.radioGroup)

            Text(L10n.t(preferences.appearanceStyle.guideKey))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if preferences.appearanceStyle.usesHoleAndConnector {
                LabeledContent(L10n.t("appearance.hole")) {
                    Text(L10n.t("appearance.hole.value")).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(L10n.t("appearance.section.style"))
        } footer: {
            Text(L10n.t("appearance.style.footer"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func sampleLabel(for role: TagColorRole) -> String {
        switch role {
        case .active: return "GR"
        case .attention: return "OD"
        case .aging: return "ML"
        case .stale: return "PhD"
        case .paused: return "II"
        case .archived: return "OK"
        }
    }

    private func dayStepper(title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Stepper(value: value, in: range) {
                Text(L10n.t("appearance.days", value.wrappedValue))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
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
                Button(L10n.t("common.default")) { value.wrappedValue = defaultValue }
                    .controlSize(.small)
            }
        }
    }
}

/// A miniature tag, drawn with exactly the same colour rules as the real tabs.
struct TagSwatch: View {
    let role: TagColorRole
    let label: String
    let isDark: Bool

    var body: some View {
        let background = EdgeTagStyle.backgroundColor(role: role, isDark: isDark)
        let foreground = EdgeTagStyle.textColor(role: role, isDark: isDark)
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(nsColor: foreground))
            .lineLimit(1)
            .frame(width: 52, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(Color(nsColor: background))
            )
    }
}
