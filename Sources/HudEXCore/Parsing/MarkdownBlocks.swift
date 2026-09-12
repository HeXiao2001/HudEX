import Foundation

/// A block of Markdown body text.
///
/// HudEX renders Markdown with Apple's own tooling (`AttributedString(markdown:)`
/// for inline runs plus SwiftUI `Text`), so the only job left here is deciding
/// which lines form a paragraph, a list, or a small heading. That decision is
/// pure logic and therefore lives in Core, where it is unit tested.
public enum MarkdownBlock: Equatable, Sendable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case bulletList(items: [String])
    case numberedList(items: [MarkdownListItem])
    case quote(String)
    case codeBlock(String)
}

public struct MarkdownListItem: Equatable, Sendable {
    /// Number as written (`1.`, `2.` …), preserved so the text round-trips.
    public let number: String
    public let text: String
}

/// Splits a section body into renderable blocks.
public enum MarkdownBlockParser {
    public static func blocks(from body: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")

        var paragraph: [String] = []
        var bullets: [String] = []
        var numbered: [MarkdownListItem] = []
        var quote: [String] = []
        var code: [String] = []
        var inCode = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }
        func flushBullets() {
            guard !bullets.isEmpty else { return }
            blocks.append(.bulletList(items: bullets))
            bullets.removeAll()
        }
        func flushNumbered() {
            guard !numbered.isEmpty else { return }
            blocks.append(.numberedList(items: numbered))
            numbered.removeAll()
        }
        func flushQuote() {
            guard !quote.isEmpty else { return }
            blocks.append(.quote(quote.joined(separator: "\n")))
            quote.removeAll()
        }
        func flushAll() {
            flushParagraph()
            flushBullets()
            flushNumbered()
            flushQuote()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if inCode {
                    blocks.append(.codeBlock(code.joined(separator: "\n")))
                    code.removeAll()
                    inCode = false
                } else {
                    flushAll()
                    inCode = true
                }
                continue
            }
            if inCode {
                code.append(line)
                continue
            }

            if trimmed.isEmpty {
                flushAll()
                continue
            }

            if let heading = MarkdownHeading.parse(line), heading.level >= 3 {
                flushAll()
                blocks.append(.heading(level: heading.level, text: heading.text))
                continue
            }

            if let item = bulletItem(trimmed) {
                flushParagraph()
                flushNumbered()
                flushQuote()
                bullets.append(item)
                continue
            }

            if let item = numberedItem(trimmed) {
                flushParagraph()
                flushBullets()
                flushQuote()
                numbered.append(item)
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushBullets()
                flushNumbered()
                quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }

            flushBullets()
            flushNumbered()
            flushQuote()
            paragraph.append(line)
        }

        if inCode, !code.isEmpty {
            blocks.append(.codeBlock(code.joined(separator: "\n")))
        }
        flushAll()
        return blocks
    }

    private static func bulletItem(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func numberedItem(_ line: String) -> MarkdownListItem? {
        var digits = ""
        var index = line.startIndex
        while index < line.endIndex, line[index].isNumber, digits.count < 3 {
            digits.append(line[index])
            index = line.index(after: index)
        }
        guard !digits.isEmpty, index < line.endIndex else { return nil }
        let separator = line[index]
        guard separator == "." || separator == ")" || separator == "、" else { return nil }
        let rest = String(line[line.index(after: index)...])
        guard rest.hasPrefix(" ") || rest.hasPrefix("\t") else { return nil }
        return MarkdownListItem(number: digits, text: rest.trimmingCharacters(in: .whitespaces))
    }
}
