import AppKit
import HudEXCore
import SwiftUI

/// The first thing a new user sees: pick the Markdown file, pick a style.
///
/// It only exists while HudEX has nothing to show — once a file parses into at
/// least one project this pane disappears from the tab bar, and Settings opens
/// on General like it does for everyone else.
struct WelcomeSettingsView: View {
    @ObservedObject private var preferences = Preferences.shared
    @ObservedObject private var controller = HudEXController.shared
    @Environment(\.colorScheme) private var colorScheme

    private var path: String { controller.documentSummary.path }
    private var fileExists: Bool { FileManager.default.fileExists(atPath: path) }

    var body: some View {
        Form {
            Section {
                Text(L10n.t("welcome.intro"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(L10n.t("welcome.title"))
            }

            fileStep
            styleStep
        }
        .formStyle(.grouped)
    }

    // MARK: - Step 1: the file

    private var fileStep: some View {
        Section {
            LabeledContent(L10n.t("welcome.step1.location")) {
                Text(path)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            statusRow

            HStack(spacing: 8) {
                Button(L10n.t("welcome.step1.useDefault")) { useDefaultLocation() }
                Button(L10n.t("source.choose")) { controller.chooseMarkdownFile() }
                if !fileExists {
                    Button(L10n.t("source.createExample")) { createTemplate() }
                }
                Button(L10n.t("source.reload")) { controller.reloadDocument() }
            }

            if !isUsable {
                Text(L10n.t("welcome.step1.fixHint"))
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(L10n.t("welcome.step1"))
        } footer: {
            Text(L10n.t("welcome.step1.footer"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            Image(systemName: isUsable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isUsable ? Color.green : Color.orange)
            Text(statusText)
                .font(.callout)
            Spacer()
        }
    }

    private var statusText: String {
        if !fileExists { return L10n.t("welcome.status.missing") }
        if controller.documentSummary.projectCount == 0 { return L10n.t("welcome.status.empty") }
        return L10n.t("welcome.status.found", controller.documentSummary.projectCount)
    }

    private var isUsable: Bool { controller.hasUsableDocument }

    private func useDefaultLocation() {
        let url = Preferences.defaultSourceURL
        controller.setSourceURL(url)
        if !FileManager.default.fileExists(atPath: url.path) {
            controller.createExampleFile(at: url)
        }
    }

    private func createTemplate() {
        controller.createExampleFile(at: URL(fileURLWithPath: path))
    }

    // MARK: - Step 2: the style

    private var styleStep: some View {
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
            Text(L10n.t("welcome.step2"))
        } footer: {
            Text(L10n.t("welcome.step2.footer"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
