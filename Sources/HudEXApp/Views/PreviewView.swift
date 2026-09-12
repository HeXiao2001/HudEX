import HudEXCore
import SwiftUI

/// The hover preview: project name, 当前 / 下一步 / 最新对话.
///
/// Purely informational — no buttons. Editing lives in the menu bar
/// ("打开 Markdown 文件"), and the full project text is one right-click away on
/// the tag itself. Keeping the panel free of controls means it never takes
/// key-window status and stays cheap while the pointer moves.
struct PreviewView: View {
    let model: PreviewModel

    static let width: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            ForEach(model.sections) { section in
                SectionBlockView(
                    title: section.title,
                    text: section.body,
                    lineLimit: section.singleLine ? 1 : 4
                )
                .padding(.top, 2)
            }

            if let hint = model.emptyHint {
                Text(hint)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(width: Self.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if let age = model.relativeAge {
                    Text(age)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                Text(model.statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let updated = model.updatedLine {
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text(updated)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// The full project text. Reached by right-clicking a tag → “打开项目完整内容”,
/// never by a button inside the hover preview.
struct DetailView: View {
    let model: DetailModel
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if let preamble = model.preamble, !preamble.isEmpty {
                        MarkdownBodyView(markdown: preamble)
                    }

                    ForEach(model.sections) { section in
                        SectionBlockView(title: section.title, text: section.body)
                    }

                    if model.sections.isEmpty {
                        Text("这个项目还没有任何 三级标题 小节。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Spacer()
                Button("编辑", action: onEdit)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 380, minHeight: 320)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.title)
                .font(.system(size: 18, weight: .semibold))
                .textSelection(.enabled)

            HStack(spacing: 6) {
                Text("状态：\(model.statusText)")
                if let updated = model.updatedLine {
                    Text("·")
                    Text(updated)
                }
                if let age = model.relativeAge {
                    Text("·")
                    Text(age)
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)

            Divider()
                .padding(.top, 2)
        }
    }
}
