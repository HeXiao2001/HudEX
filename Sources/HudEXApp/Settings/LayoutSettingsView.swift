import HudEXCore
import SwiftUI

/// Layout settings.
///
/// HudEX reads the Dock's edge and thickness from the system at launch and when
/// macOS reports a screen change — it never watches the Dock continuously — and
/// everything about placement can be pinned down here instead.
struct LayoutSettingsView: View {
    @ObservedObject private var preferences = Preferences.shared
    @ObservedObject private var controller = HudEXController.shared

    var body: some View {
        Form {
            modeSection
            geometrySection
            slotsSection
            sizeSection
            countSection
            spacingSection
            calibrationSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Mode

    private var modeSection: some View {
        Section {
            Picker(L10n.t("layout.mode"), selection: $preferences.layoutKind) {
                Text(L10n.t("layout.mode.dockAdaptive")).tag(LayoutMode.Kind.dockAdaptive)
                Text(L10n.t("layout.mode.dockSplit")).tag(LayoutMode.Kind.dockSplit)
                Text(L10n.t("layout.mode.fixedEdge")).tag(LayoutMode.Kind.fixedEdge)
            }
            .pickerStyle(.radioGroup)

            if preferences.layoutKind == .fixedEdge {
                Picker(L10n.t("layout.edge"), selection: $preferences.layoutEdge) {
                    Text(L10n.t("edge.left")).tag(DockEdge.left)
                    Text(L10n.t("edge.right")).tag(DockEdge.right)
                    Text(L10n.t("edge.bottom")).tag(DockEdge.bottom)
                }
                .pickerStyle(.segmented)

                Picker(L10n.t("layout.anchor"), selection: $preferences.layoutAnchor) {
                    Text(L10n.t("layout.anchor.start")).tag(LayoutMode.Anchor.start)
                    Text(L10n.t("layout.anchor.center")).tag(LayoutMode.Anchor.center)
                    Text(L10n.t("layout.anchor.end")).tag(LayoutMode.Anchor.end)
                }
                .pickerStyle(.segmented)

                slider(
                    title: L10n.t("layout.offset"),
                    value: $preferences.layoutOffset,
                    range: -400...400,
                    step: 5,
                    defaultValue: 0,
                    format: { "\(Int($0)) pt" }
                )
            }
        } header: {
            Text(L10n.t("layout.section.mode"))
        } footer: {
            Text(L10n.t("layout.mode.footer"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Dock geometry

    private var geometrySection: some View {
        Section {
            LabeledContent(L10n.t("layout.dock.edge")) { value(controller.geometry.edgeName) }
            LabeledContent(L10n.t("layout.dock.thickness")) { value("\(controller.geometry.thickness) pt") }
            LabeledContent(L10n.t("layout.dock.occupied")) {
                value("\(controller.geometry.occupiedStart)–\(controller.geometry.occupiedEnd) pt")
            }
            LabeledContent(L10n.t("layout.dock.source")) { value(controller.geometry.sourceName) }
            LabeledContent(L10n.t("layout.dock.screen")) { value(controller.geometry.screenName) }
        } header: {
            Text(L10n.t("layout.section.dock"))
        } footer: {
            Text(L10n.t("layout.dock.footer"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var slotsSection: some View {
        Section {
            LabeledContent(L10n.t("layout.slot.primary")) {
                value(L10n.t("layout.slot.capacity", controller.geometry.primaryRange, controller.geometry.primaryCapacity))
            }
            LabeledContent(L10n.t("layout.slot.secondary")) {
                value(L10n.t("layout.slot.capacity", controller.geometry.secondaryRange, controller.geometry.secondaryCapacity))
            }
            if controller.overflowCount > 0 {
                Text(L10n.t("layout.overflowWarning", controller.overflowCount))
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text(L10n.t("layout.section.slots"))
        } footer: {
            Text(L10n.t("layout.slots.footer"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Size

    private var sizeSection: some View {
        Section {
            slider(
                title: L10n.t("layout.size.width"),
                value: $preferences.tabProtrusion,
                range: 0...240,
                step: 1,
                defaultValue: 0,
                format: { $0 <= 0 ? L10n.t("layout.size.autoWidth", controller.geometry.thickness) : "\(Int($0)) pt" }
            )
            slider(
                title: L10n.t("layout.size.height"),
                value: $preferences.tabLength,
                range: 0...240,
                step: 1,
                defaultValue: 0,
                format: { $0 <= 0 ? L10n.t("layout.size.autoHeight") : "\(Int($0)) pt" }
            )
            slider(
                title: L10n.t("layout.size.font"),
                value: $preferences.fontSize,
                range: 0...24,
                step: 0.5,
                defaultValue: 0,
                format: { $0 <= 0 ? L10n.t("layout.size.autoFont") : String(format: "%.1f pt", $0) }
            )
            Button(L10n.t("layout.size.reset")) { preferences.resetTagSize() }
        } header: {
            Text(L10n.t("layout.section.size"))
        } footer: {
            Text(L10n.t("layout.size.footer"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Count

    private var countSection: some View {
        Section {
            HStack {
                Text(L10n.t("layout.count.max"))
                Spacer()
                Stepper(value: $preferences.maxTags, in: 0...99) {
                    Text(preferences.maxTags == 0 ? L10n.t("layout.count.unlimited") : L10n.t("layout.count.value", preferences.maxTags))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            HStack {
                Text(L10n.t("layout.count.perSlot"))
                Spacer()
                Stepper(value: $preferences.maxTagsPerSlot, in: 0...99) {
                    Text(preferences.maxTagsPerSlot == 0 ? L10n.t("layout.count.unlimited") : L10n.t("layout.count.value", preferences.maxTagsPerSlot))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } header: {
            Text(L10n.t("layout.section.count"))
        } footer: {
            Text(L10n.t("layout.count.footer"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Spacing

    private var spacingSection: some View {
        Section {
            slider(
                title: L10n.t("layout.spacing.gap"),
                value: $preferences.edgeGap,
                range: 0...60,
                step: 1,
                defaultValue: 12,
                format: { "\(Int($0)) pt" }
            )
            slider(
                title: L10n.t("layout.spacing.corner"),
                value: $preferences.cornerInset,
                range: 0...120,
                step: 1,
                defaultValue: 8,
                format: { "\(Int($0)) pt" }
            )
        } header: {
            Text(L10n.t("layout.section.spacing"))
        }
    }

    // MARK: - Calibration

    private var calibrationSection: some View {
        Section {
            slider(
                title: L10n.t("layout.calibration.thickness"),
                value: $preferences.dockThicknessOverride,
                range: 0...240,
                step: 1,
                defaultValue: 0,
                format: { $0 <= 0 ? L10n.t("layout.calibration.autoValue", controller.geometry.thickness) : "\(Int($0)) pt" }
            )
            slider(
                title: L10n.t("layout.calibration.length"),
                value: $preferences.dockLengthOverride,
                range: 0...2000,
                step: 10,
                defaultValue: 0,
                format: { value in
                    guard value > 0 else {
                        let length = controller.geometry.occupiedEnd - controller.geometry.occupiedStart
                        return L10n.t("layout.calibration.autoValue", length)
                    }
                    return "\(Int(value)) pt"
                }
            )
            HStack {
                Button(L10n.t("layout.calibration.reset")) { preferences.resetDockCalibration() }
                Button(L10n.t("layout.calibration.redetect")) { controller.resetDockGeometryCache() }
            }
        } header: {
            Text(L10n.t("layout.section.calibration"))
        } footer: {
            Text(L10n.t("layout.calibration.footer"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

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
                Button(L10n.t("common.default")) { value.wrappedValue = defaultValue }
                    .controlSize(.small)
            }
        }
    }
}
