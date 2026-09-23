import AppKit
import HudEXCore
import SwiftUI

struct SourceSettingsView: View {
    @ObservedObject private var preferences = Preferences.shared
    @ObservedObject private var controller = HudEXController.shared

    @State private var pathDraft: String = ""
    @State private var isDropping = false

    private var fileExists: Bool {
        FileManager.default.fileExists(atPath: controller.documentSummary.path)
    }

    var body: some View {
        Form {
            Section {
                // Typing or pasting a path is the light option; the system file
                // panel is only opened when it is actually wanted (it brings its
                // own caches along, especially while browsing a big folder).
                TextField(L10n.t("source.path.placeholder"), text: $pathDraft)
                    .font(.system(size: 11.5, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(applyDraft)

                HStack(spacing: 8) {
                    Button(L10n.t("source.apply")) { applyDraft() }
                        .disabled(pathDraft == controller.documentSummary.path)
                    Button(L10n.t("source.choose")) { chooseFile() }
                    Button(L10n.t("source.open")) { controller.openMarkdownFile() }
                    Button(L10n.t("source.reveal")) { controller.revealInFinder() }
                    Button(L10n.t("source.reload")) { controller.reloadDocument() }
                }

                Text(L10n.t("source.dropHint"))
                    .font(.callout)
                    .foregroundStyle(isDropping ? Color.accentColor : .secondary)
            } header: {
                Text(L10n.t("source.section.file"))
            } footer: {
                Text(L10n.t("source.footer"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropping) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, ["md", "json"].contains(url.pathExtension.lowercased()) else { return }
                    Task { @MainActor in
                        controller.setSourceURL(url)
                        pathDraft = url.path
                    }
                }
                return true
            }
            .onAppear { pathDraft = controller.documentSummary.path }
            .onChange(of: controller.documentSummary.path) { _, new in pathDraft = new }

            Section {
                Text(L10n.t("source.ownership.body"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(L10n.t("source.ownership"))
            } footer: {
                Text(L10n.t("source.ownership.footer"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            syncSection
            remindersSection

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
            if let recovered = controller.recoveredLaunch {
                Section {
                    Text(L10n.t("source.recovered", recovered.attempts))
                        .font(.callout)
                    if let report = recovered.report {
                        LabeledContent(L10n.t("source.report")) {
                            value(report.lastPathComponent)
                        }
                    }
                    HStack(spacing: 8) {
                        Button(L10n.t("source.revealReport")) { revealReports() }
                        Button(L10n.t("source.clearReports")) { clearReports() }
                    }
                } header: {
                    Text(L10n.t("source.section.recovery"))
                } footer: {
                    Text(L10n.t("source.recovered.footer"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
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
                HStack(spacing: 8) {
                    Button(L10n.t("advanced.reload")) { controller.reloadDocument() }
                    Button(L10n.t("advanced.clearGeometry")) { controller.resetDockGeometryCache() }
                    Button(L10n.t("advanced.copyDiagnostics")) { copyDiagnostics() }
                }
            } header: {
                Text(L10n.t("advanced.section.diagnostics"))
            } footer: {
                Text(L10n.t("advanced.permissions.footer"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
            .disabled(controller.store.document.format == .json)
        } header: {
            Text(L10n.t("sync.section"))
        } footer: {
            Text(L10n.t("sync.footer"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var remindersSection: some View {
        Section {
            if controller.store.document.format == .markdown {
                Button(L10n.t("reminders.convert")) { controller.convertSourceToJSON() }
                Text(L10n.t("reminders.convertHint"))
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Toggle(L10n.t("reminders.autoSync"), isOn: $preferences.remindersAutoSyncEnabled)
                Button(L10n.t("reminders.syncNow")) { controller.syncRemindersNow() }
                    .disabled(controller.remindersSyncing)
            }
            if let status = controller.remindersSyncStatus {
                Text(status).font(.callout).foregroundStyle(.secondary)
            }
        } header: {
            Text(L10n.t("reminders.section"))
        } footer: {
            Text(L10n.t("reminders.footer"))
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func value(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary)
    }

    private func revealReports() {
        let folder = LaunchGuard.reportFolder
        if let folder, FileManager.default.fileExists(atPath: folder.path) {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs"))
        }
    }

    private func clearReports() {
        if let folder = LaunchGuard.reportFolder {
            try? FileManager.default.removeItem(at: folder)
        }
        controller.clearRecoveredLaunch()
    }

    private func copyDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(controller.diagnosticsText, forType: .string)
    }

    /// Standard open panel; the app is not sandboxed, so a plain path suffices.
    private func chooseFile() {
        controller.chooseMarkdownFile()
    }

    private func applyDraft() {
        let trimmed = pathDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let expanded = (trimmed as NSString).expandingTildeInPath
        controller.setSourceURL(URL(fileURLWithPath: expanded))
    }
}
