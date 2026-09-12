import AppKit
import HudEXCore
import SwiftUI

struct SourceSettingsView: View {
    @ObservedObject private var preferences = Preferences.shared
    @ObservedObject private var controller = HudEXController.shared

    private var fileExists: Bool {
        FileManager.default.fileExists(atPath: controller.documentSummary.path)
    }

    var body: some View {
        Form {
            Section {
                Text(controller.documentSummary.path)
                    .font(.system(size: 11.5, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button(L10n.t("source.choose")) { chooseFile() }
                    Button(L10n.t("source.open")) { controller.openMarkdownFile() }
                    Button(L10n.t("source.reveal")) { controller.revealInFinder() }
                    Button(L10n.t("source.reload")) { controller.reloadDocument() }
                }
            } header: {
                Text(L10n.t("source.section.file"))
            } footer: {
                Text(L10n.t("source.footer"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            syncSection

            Section {
                if fileExists {
                    if let loadedAt = controller.documentSummary.loadedAt {
                        LabeledContent(L10n.t("source.lastLoaded")) {
                            value(TimestampFormatter.string(from: loadedAt))
                        }
                    }
                    LabeledContent(L10n.t("general.projectCount")) {
                        value("\(controller.documentSummary.projectCount)")
                    }
                } else {
                    Text(L10n.t("source.missingHint")).font(.callout)
                    Button(L10n.t("source.createExample")) {
                        controller.createExampleFile(at: URL(fileURLWithPath: controller.documentSummary.path))
                    }
                }
            } header: {
                Text(L10n.t("source.section.status"))
            }

            if let status = controller.documentSummary.statusMessage {
                Section { Text(status).font(.callout).foregroundStyle(.secondary) }
            }
            if let error = controller.documentSummary.errorMessage {
                Section { Text(error).font(.callout).foregroundStyle(.red) }
            }
            if !controller.documentSummary.warnings.isEmpty {
                Section {
                    ForEach(Array(controller.documentSummary.warnings.enumerated()), id: \.offset) { _, warning in
                        Text(warning).font(.callout).foregroundStyle(.secondary)
                    }
                } header: {
                    Text(L10n.t("source.section.warnings"))
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Two-way settings sync with the Markdown file.
    private var syncSection: some View {
        Section {
            Toggle(L10n.t("sync.writeBack"), isOn: $preferences.settingsWriteBack)
            LabeledContent(L10n.t("sync.lastWrite")) {
                value(controller.lastSettingsWrite.map(TimestampFormatter.string(from:)) ?? L10n.t("sync.never"))
            }
            HStack(spacing: 8) {
                Button(L10n.t("sync.writeNow")) { controller.writeSettingsToMarkdown() }
                Button(L10n.t("sync.readNow")) { controller.applySettingsFromMarkdown() }
            }
        } header: {
            Text(L10n.t("sync.section"))
        } footer: {
            Text(L10n.t("sync.footer"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func value(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary)
    }

    /// Standard open panel; the app is not sandboxed, so a plain path suffices.
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = L10n.t("source.panel.title")
        panel.prompt = L10n.t("source.panel.prompt")
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText, .plainText]
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: controller.documentSummary.path).deletingLastPathComponent()

        if panel.runModal() == .OK, let url = panel.url {
            controller.setSourceURL(url)
        }
    }
}
