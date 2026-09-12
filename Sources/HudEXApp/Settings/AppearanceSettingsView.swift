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

            StyleSampleView(style: preferences.appearanceStyle, isDark: colorScheme == .dark)
                .frame(height: 118)
                .frame(maxWidth: .infinity)

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

/// A miniature of the selected style: one tag and the card it opens, so the
/// choice is visible without hovering the real tags.
struct StyleSampleView: View {
    let style: AppearanceStyle
    let isDark: Bool

    private let sampleRole: TagColorRole = .attention   // the amber "OD" look

    var body: some View {
        let tag = EdgeTagStyle.backgroundColor(role: sampleRole, isDark: isDark)
        let tagText = EdgeTagStyle.textColor(role: sampleRole, isDark: isDark)
        let paper = TagPalette.color(for: sampleRole, isDark: isDark)
        let appearance = TagAppearanceResolver.appearance(role: sampleRole, colorOverride: nil, isDark: isDark)

        HStack(alignment: .center, spacing: style.usesHoleAndConnector ? 10 : 8) {
            ZStack {
                RoundedRectangle(cornerRadius: style == .minimal ? 3 : 5, style: .continuous)
                    .fill(style == .minimal ? Color.clear : Color(nsColor: tag))
                if style == .minimal {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Color(nsColor: tag), lineWidth: 1)
                }
                if style == .skeuomorphic {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.22), .black.opacity(0.14)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                Text("OD")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(style == .minimal ? Color(nsColor: tag) : Color(nsColor: tagText))
                if style.usesHoleAndConnector {
                    Circle()
                        .fill(Color(nsColor: EdgeTagStyle.color(ProjectPriority.high.holeColor(isDark: isDark))))
                        .frame(width: 6, height: 6)
                        .offset(x: 20)
                }
            }
            .frame(width: 52, height: 24)

            if style.usesHoleAndConnector {
                ConnectorSample(color: Color(nsColor: EdgeTagStyle.color(appearance.rule(isDark: isDark))))
                    .frame(width: 26, height: 40)
            }

            sampleCard(paper: paper, appearance: appearance)
                .frame(width: 132, height: style == .glass ? 84 : 90)
        }
        .frame(maxWidth: .infinity)
        .padding(6)
    }

    @ViewBuilder
    private func sampleCard(paper: PaletteColor, appearance: TagAppearance) -> some View {
        let shape = RoundedRectangle(cornerRadius: style == .glass ? 12 : 6, style: .continuous)
        ZStack(alignment: .topLeading) {
            switch style {
            case .skeuomorphic:
                shape.fill(Color(nsColor: EdgeTagStyle.color(appearance.paper(isDark: isDark))))
                VStack(spacing: 14) {
                    ForEach(0..<4, id: \.self) { _ in
                        Rectangle()
                            .fill(Color(nsColor: EdgeTagStyle.color(appearance.rule(isDark: isDark))).opacity(0.6))
                            .frame(height: 0.8)
                    }
                }
                .padding(.top, 24)
                .padding(.horizontal, 8)
            case .frosted:
                shape.fill(.regularMaterial)
            case .glass:
                shape.fill(.ultraThinMaterial)
            case .minimal:
                shape.fill(Color.clear)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t("appearance.sample.title"))
                    .font(.system(size: 11, weight: .semibold))
                Text(L10n.t("appearance.sample.body"))
                    .font(.system(size: 10))
                    .opacity(0.7)
                    .lineLimit(2)
            }
            .padding(10)
            .foregroundStyle(style == .skeuomorphic
                ? Color(nsColor: EdgeTagStyle.color(appearance.ink(isDark: isDark)))
                : Color.primary)

            shape.strokeBorder(
                style == .minimal
                    ? Color(nsColor: EdgeTagStyle.color(TagPalette.color(for: sampleRole, isDark: isDark)))
                    : Color.white.opacity(isDark ? 0.14 : 0.4),
                lineWidth: 1
            )
        }
    }
}

/// The little curved string in the sample.
private struct ConnectorSample: View {
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let start = CGPoint(x: 0, y: geometry.size.height / 2)
                let end = CGPoint(x: geometry.size.width, y: geometry.size.height)
                path.move(to: start)
                path.addCurve(
                    to: end,
                    control1: CGPoint(x: geometry.size.width * 0.4, y: start.y),
                    control2: CGPoint(x: geometry.size.width * 0.6, y: end.y)
                )
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
    }
}
