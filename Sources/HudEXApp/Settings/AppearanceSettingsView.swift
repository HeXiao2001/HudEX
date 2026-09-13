import HudEXCore
import SwiftUI

/// Appearance: the style picker (each option previews itself), the hover
/// preview switch, the stacking controls and the colour thresholds.
struct AppearanceSettingsView: View {
    @ObservedObject private var preferences = Preferences.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    ForEach(AppearanceStyle.allCases, id: \.self) { style in
                        StyleCardView(
                            style: style,
                            isSelected: preferences.appearanceStyle == style,
                            isDark: colorScheme == .dark
                        ) {
                            preferences.appearanceStyle = style
                        }
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text(L10n.t("appearance.section.style"))
            } footer: {
                Text(L10n.t(preferences.appearanceStyle.guideKey))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(L10n.t("appearance.showUpdatedTime"), isOn: $preferences.showUpdatedTime)
            } header: {
                Text(L10n.t("appearance.section.preview"))
            }

            Section {
                Toggle(L10n.t("appearance.stack.enabled"), isOn: $preferences.stackEnabled)
                SliderRow(
                    title: L10n.t("appearance.stack.overlap"),
                    value: $preferences.stackOverlap,
                    range: 0...0.8,
                    step: 0.02,
                    defaultValue: 0.34,
                    format: { String(format: "%.0f%%", $0 * 100) }
                )
                SliderRow(
                    title: L10n.t("appearance.stack.rotation"),
                    value: $preferences.stackRotation,
                    range: -20...20,
                    step: 1,
                    defaultValue: -5,
                    format: { String(format: "%.0f°", $0) }
                )
                SliderRow(
                    title: L10n.t("appearance.stack.stagger"),
                    value: $preferences.stackStagger,
                    range: 0...12,
                    step: 0.5,
                    defaultValue: 2.5,
                    format: { String(format: "%.1f pt", $0) }
                )
            } header: {
                Text(L10n.t("appearance.section.stack"))
            }

            Section {
                DayStepper(
                    title: L10n.t("appearance.color.active"),
                    value: $preferences.thresholdActive,
                    range: 0...60
                )
                DayStepper(
                    title: L10n.t("appearance.color.attention"),
                    value: $preferences.thresholdAttention,
                    range: 1...120
                )
                DayStepper(
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
        }
        .formStyle(.grouped)
    }
}

/// One style option, drawn as the thing it produces: a tag, its string and the
/// card it opens.
struct StyleCardView: View {
    let style: AppearanceStyle
    let isSelected: Bool
    let isDark: Bool
    let action: () -> Void

    private let sampleRole: TagColorRole = .attention

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                artwork
                    .frame(height: 62)
                Text(L10n.t(style.shortNameKey))
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(isSelected ? 0.10 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var artwork: some View {
        let tag = EdgeTagStyle.backgroundColor(role: sampleRole, isDark: isDark)
        let tagText = EdgeTagStyle.textColor(role: sampleRole, isDark: isDark)
        let appearance = TagAppearanceResolver.appearance(role: sampleRole, colorOverride: nil, isDark: isDark)

        return HStack(spacing: style.usesHoleAndConnector ? 2 : 6) {
            ZStack {
                RoundedRectangle(cornerRadius: style == .minimal ? 3 : 5, style: .continuous)
                    .fill(style == .minimal ? Color.clear : Color(nsColor: tag))
                if style == .minimal {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Color(nsColor: tag), lineWidth: 1)
                }
                Text(L10n.t("appearance.sample.tag"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(style == .minimal ? Color(nsColor: tag) : Color(nsColor: tagText))
                if style.usesHoleAndConnector {
                    Circle()
                        .fill(Color(nsColor: EdgeTagStyle.color(ProjectPriority.high.holeColor(isDark: isDark))))
                        .frame(width: 4, height: 4)
                        .offset(x: 15)
                }
            }
            .frame(width: 40, height: 19)

            if style.usesHoleAndConnector {
                SampleString(color: Color(nsColor: EdgeTagStyle.color(appearance.rule(isDark: isDark))))
                    .frame(width: 18, height: 30)
            }

            card(appearance: appearance)
                .frame(width: 66, height: 52)
        }
    }

    @ViewBuilder
    private func card(appearance: TagAppearance) -> some View {
        let shape = RoundedRectangle(cornerRadius: style == .frosted ? 10 : 5, style: .continuous)
        ZStack(alignment: .topLeading) {
            switch style {
            case .skeuomorphic:
                shape.fill(Color(nsColor: EdgeTagStyle.color(appearance.paper(isDark: isDark))))
            case .frosted:
                shape.fill(.regularMaterial)
            case .minimal:
                shape.fill(Color.clear)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("appearance.sample.title"))
                    .font(.system(size: 8, weight: .semibold))
                ForEach(0..<3, id: \.self) { _ in
                    Rectangle()
                        .fill(
                            style == .skeuomorphic
                                ? Color(nsColor: EdgeTagStyle.color(appearance.rule(isDark: isDark))).opacity(0.45)
                                : Color.primary.opacity(0.25)
                        )
                        .frame(height: 0.7)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 7)
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

/// The little curved string in a style preview.
private struct SampleString: View {
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let start = CGPoint(x: 0, y: geometry.size.height * 0.35)
                let end = CGPoint(x: geometry.size.width, y: geometry.size.height * 0.6)
                path.move(to: start)
                path.addCurve(
                    to: end,
                    control1: CGPoint(x: geometry.size.width * 0.7, y: start.y - 4),
                    control2: CGPoint(x: geometry.size.width * 0.3, y: end.y + 4)
                )
            }
            .stroke(color.opacity(0.85), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
        }
    }
}

/// A labelled slider with a reset button, used across the settings panes.
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let defaultValue: Double
    var format: (Double) -> String = { String(format: "%.0f", $0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: step)
                Button(L10n.t("common.default")) { value = defaultValue }
                    .controlSize(.small)
            }
        }
    }
}

/// A day-count stepper used by the colour thresholds.
struct DayStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Stepper(value: $value, in: range) {
                Text(L10n.t("appearance.days", value))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
