import AppKit
import HudEXCore
import SwiftUI

struct AdvancedSettingsView: View {
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
                .frame(height: 190)

                HStack(spacing: 8) {
                    Button(L10n.t("advanced.reload")) { controller.reloadDocument() }
                    Button(L10n.t("advanced.clearGeometry")) { controller.resetDockGeometryCache() }
                    Button(L10n.t("advanced.copyDiagnostics")) { copyDiagnostics() }
                }
            } header: {
                Text(L10n.t("advanced.section.diagnostics"))
            }

            Section {
                LabeledContent(L10n.t("advanced.accessibility")) { value(L10n.t("advanced.notUsed")) }
                LabeledContent(L10n.t("advanced.screenRecording")) { value(L10n.t("advanced.notUsed")) }
                LabeledContent(L10n.t("advanced.network")) { value(L10n.t("advanced.none")) }
            } header: {
                Text(L10n.t("advanced.section.permissions"))
            } footer: {
                Text(L10n.t("advanced.permissions.footer"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent(L10n.t("advanced.memory")) {
                    value(String(format: "%.1f MB", controller.performance.residentMegabytes))
                }
                LabeledContent(L10n.t("advanced.cpu")) {
                    value(L10n.t("advanced.cpuValue",
                                 controller.performance.cpuTimeSeconds,
                                 controller.performance.averageCPUPercent))
                }
                LabeledContent(L10n.t("advanced.threads")) {
                    value("\(controller.performance.threadCount)")
                }
            } header: {
                Text(L10n.t("advanced.section.resources"))
            } footer: {
                Text(L10n.t("advanced.resources.footer"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent(L10n.t("advanced.structure")) {
                    value(L10n.t("advanced.structure.value"))
                }
                LabeledContent(L10n.t("advanced.logging")) {
                    value(L10n.t("advanced.logging.value"))
                }
            } header: {
                Text(L10n.t("advanced.section.maintenance"))
            }
        }
        .formStyle(.grouped)
    }

    private func value(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary)
    }

    private func copyDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(controller.diagnosticsText, forType: .string)
    }
}
