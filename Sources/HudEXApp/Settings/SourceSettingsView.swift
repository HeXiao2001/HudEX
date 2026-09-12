import AppKit
import HudEXCore
import SwiftUI

struct SourceSettingsView: View {
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
                    Button("选择文件…") { chooseFile() }
                    Button("打开文件") { controller.openMarkdownFile() }
                    Button("在 Finder 中显示") { controller.revealInFinder() }
                    Button("重新载入") { controller.reloadDocument() }
                }
            } header: {
                Text("HudEX.md")
            } footer: {
                Text("HudEX 只读取本地已经同步好的 Markdown 文件，不连接 OneDrive，也不写入内容。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                if fileExists {
                    if let loadedAt = controller.documentSummary.loadedAt {
                        LabeledContent("最近载入") {
                            Text(TimestampFormatter.string(from: loadedAt))
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("项目数") {
                        Text("\(controller.documentSummary.projectCount)")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(HudEXTemplate.missingFileHint)
                        .font(.callout)
                    Button("创建示例文件") {
                        controller.createExampleFile(at: URL(fileURLWithPath: controller.documentSummary.path))
                    }
                }
            } header: {
                Text("状态")
            }

            if let status = controller.documentSummary.statusMessage {
                Section {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = controller.documentSummary.errorMessage {
                Section {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            if !controller.documentSummary.warnings.isEmpty {
                Section {
                    ForEach(Array(controller.documentSummary.warnings.enumerated()), id: \.offset) { _, warning in
                        Text(warning)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("解析提示")
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Uses the standard open panel; the app is not sandboxed, so the plain
    /// path is enough and no extra entitlement is needed.
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "选择 HudEX.md"
        panel.prompt = "选择"
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
