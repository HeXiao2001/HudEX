import HudEXCore
import SwiftUI

/// Renders Markdown body text with Apple's own parser and SwiftUI text.
///
/// There is no WebView, no HTML step and no remote content: images and embeds
/// are removed before parsing, and only `http`/`https` links survive.
struct MarkdownBodyView: View {
    let markdown: String
    var font: Font = .system(size: 12.5)
    var lineSpacing: CGFloat = 7
    var lineLimit: Int?

    var body: some View {
        let blocks = MarkdownBlockParser.blocks(from: markdown)
        VStack(alignment: .leading, spacing: lineSpacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            inlineText(text)
                .lineLimit(lineLimit)

        case .heading(let level, let text):
            inlineText(text)
                .font(font.weight(level <= 4 ? .semibold : .medium))
                .foregroundStyle(.primary)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                            .font(font)
                            .foregroundStyle(.secondary)
                        inlineText(item)
                    }
                }
            }
            .lineLimit(lineLimit)

        case .numberedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(item.number).")
                            .font(font)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        inlineText(item.text)
                    }
                }
            }
            .lineLimit(lineLimit)

        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 2)
                inlineText(text)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(lineLimit)

        case .codeBlock(let text):
            Text(text)
                .font(.system(size: font.pointSizeOrNil ?? 11.5, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(lineLimit)
        }
    }

    private func inlineText(_ source: String) -> some View {
        let result = InlineMarkdown.attributed(from: source)
        return Text(result.attributed)
            .font(font)
            .textSelection(.enabled)
    }
}

private extension Font {
    /// SwiftUI does not expose a point size from `Font`; callers only use the
    /// default value here, so a fixed fallback is enough.
    var pointSizeOrNil: CGFloat? { nil }
}

/// A section title + body, used by both the preview and the detail window.
struct SectionBlockView: View {
    let title: String
    let text: String
    var lineLimit: Int?
    var titleColor: Color = .secondary
    var bodyColor: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(titleColor)
            MarkdownBodyView(markdown: text, lineLimit: lineLimit)
        }
    }
}
