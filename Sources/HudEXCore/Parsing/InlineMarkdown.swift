import Foundation

/// Turns Markdown source into an `AttributedString` using Apple's own parser.
///
/// HudEX never converts Markdown to HTML and never loads anything from the
/// network: images, attachments and embedded media are stripped before parsing,
/// so the result can only contain text, emphasis and ordinary web links.
public enum InlineMarkdown {
    public struct Result: Sendable {
        public var attributed: AttributedString
        public var diagnostics: [ParseDiagnostic]

        public init(attributed: AttributedString, diagnostics: [ParseDiagnostic] = []) {
            self.attributed = attributed
            self.diagnostics = diagnostics
        }
    }

    /// Parses inline Markdown, degrading to plain text instead of failing.
    public static func attributed(from markdown: String) -> Result {
        let stripped = stripUnsupportedSyntax(markdown)
        var diagnostics: [ParseDiagnostic] = []

        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )

        do {
            var attributed = try AttributedString(markdown: stripped, options: options)
            sanitizeLinks(&attributed)
            return Result(attributed: attributed, diagnostics: diagnostics)
        } catch {
            diagnostics.append(
                ParseDiagnostic(
                    severity: .warning,
                    message: "Markdown 渲染失败，已降级为纯文本：\(error.localizedDescription)"
                )
            )
            return Result(attributed: AttributedString(stripped), diagnostics: diagnostics)
        }
    }

    /// Plain text with all Markdown syntax removed — used for menu previews and
    /// accessibility labels.
    public static func plainText(from markdown: String) -> String {
        let result = attributed(from: markdown)
        return String(result.attributed.characters)
    }

    /// Removes everything HudEX must not render: images and embedded media.
    /// Image alt text is kept, so `![实验图](x.png)` still reads as "实验图".
    public static func stripUnsupportedSyntax(_ markdown: String) -> String {
        var text = markdown
        text = text.replacingOccurrences(
            of: #"!\[([^\]]*)\]\([^)]*\)"#,
            with: "$1",
            options: .regularExpression
        )
        // Reference-style images: ![alt][id]
        text = text.replacingOccurrences(
            of: #"!\[([^\]]*)\]\[[^\]]*\]"#,
            with: "$1",
            options: .regularExpression
        )
        // HTML/embed tags such as <img src="…"> or <iframe>.
        text = text.replacingOccurrences(
            of: #"<(img|iframe|video|audio|object|embed|script|style)\b[^>]*>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"</?(img|iframe|video|audio|object|embed|script|style)\s*/?>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // Obsidian-style embeds: ![[note]]
        text = text.replacingOccurrences(
            of: #"!\[\[[^\]]*\]\]"#,
            with: "",
            options: .regularExpression
        )
        return text
    }

    /// Drops any link whose scheme is not http/https, so HudEX can only ever
    /// hand an ordinary web page to the default browser.
    private static func sanitizeLinks(_ attributed: inout AttributedString) {
        for run in attributed.runs {
            guard let url = run.link else { continue }
            let scheme = url.scheme?.lowercased()
            if scheme != "http" && scheme != "https" {
                attributed[run.range].link = nil
            }
        }
    }
}
