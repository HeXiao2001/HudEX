import Foundation

/// Parses the human-owned `HudEX.md` file into projects.
///
/// The grammar is deliberately tiny and forgiving:
///
/// ```markdown
/// # HudEX                        ← optional document title
///
/// ## GeoRule                     ← one project per `##` heading
/// 短名：GR                        ← optional metadata (短名 / 状态 / 更新)
/// 状态：进行中
/// 更新：2026-09-12 16:30
///
/// ### 当前                       ← sections, any heading text is allowed
/// free Markdown text
///
/// ### 最新对话
/// 模型发展总结20260907
/// ```
///
/// Rules that matter for reliability:
/// * Unknown `###` headings are kept as ordinary sections.
/// * Unparsable dates never fail the parse; the raw text is preserved.
/// * A malformed file yields diagnostics and whatever could be read, never a
///   crash and never an empty document that wipes the UI.
public struct MarkdownProjectParser: @unchecked Sendable {
    public struct Options: Sendable {
        public var shortTitleKeys: [String]
        public var statusKeys: [String]
        public var updatedKeys: [String]
        /// Lines that close the current section (project separators).
        public var separatorLines: Set<String>
        public var maxShortTitleLength: Int

        public init(
            shortTitleKeys: [String] = ["短名", "简称", "缩写", "short", "shortname", "short_name", "abbr", "abbreviation"],
            statusKeys: [String] = ["状态", "status"],
            updatedKeys: [String] = ["更新", "更新时间", "最后更新", "updated", "updatedat", "updated_at", "date"],
            separatorLines: Set<String> = ["---", "***", "___", "----"],
            maxShortTitleLength: Int = ShortTitle.maxLength
        ) {
            self.shortTitleKeys = shortTitleKeys
            self.statusKeys = statusKeys
            self.updatedKeys = updatedKeys
            self.separatorLines = separatorLines
            self.maxShortTitleLength = maxShortTitleLength
        }

        public static let `default` = Options()
    }

    private let options: Options
    private let dateParser: MarkdownDateParser

    public init(options: Options = .default, dateParser: MarkdownDateParser = MarkdownDateParser()) {
        self.options = options
        self.dateParser = dateParser
    }

    public func parse(
        _ text: String,
        fileModifiedAt: Date? = nil,
        now: Date = Date()
    ) -> HudEXDocument {
        var documentTitle: String?
        var diagnostics: [ParseDiagnostic] = []
        let builder = DocumentBuilder(options: options, dateParser: dateParser)

        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if options.separatorLines.contains(trimmed) {
                builder.closeSection()
                continue
            }

            if let heading = MarkdownHeading.parse(line) {
                switch heading.level {
                case 1:
                    if documentTitle == nil, builder.hasNoProject {
                        documentTitle = heading.text
                    } else {
                        builder.appendContent(line)
                    }
                case 2:
                    builder.startProject(title: heading.text, line: lineNumber)
                default:
                    if builder.hasProject {
                        builder.startSection(title: heading.text, level: heading.level, line: lineNumber)
                    } else if !heading.text.isEmpty {
                        diagnostics.append(
                            ParseDiagnostic(
                                severity: .warning,
                                message: "标题 “\(heading.text)” 出现在任何项目之前，已忽略。",
                                line: lineNumber
                            )
                        )
                    }
                }
                continue
            }

            builder.appendContent(line)
        }

        let projects = builder.finish()
        diagnostics.append(contentsOf: builder.diagnostics)
        if projects.isEmpty {
            diagnostics.append(
                ParseDiagnostic(
                    severity: .warning,
                    message: "没有找到任何项目：请用 “## 项目名” 作为二级标题。"
                )
            )
        }

        return HudEXDocument(
            title: documentTitle,
            projects: projects,
            diagnostics: diagnostics,
            parsedAt: now,
            fileModifiedAt: fileModifiedAt
        )
    }
}

// MARK: - Headings

struct MarkdownHeading {
    let level: Int
    let text: String

    /// Parses ATX headings (`#`, `##`, …). Returns `nil` for ordinary lines.
    static func parse(_ line: String) -> MarkdownHeading? {
        var index = line.startIndex
        var hashes = 0
        while index < line.endIndex, line[index] == "#", hashes < 7 {
            hashes += 1
            index = line.index(after: index)
        }
        guard hashes >= 1, hashes <= 6, index < line.endIndex, line[index] == " " || line[index] == "\t" else {
            return nil
        }
        var text = String(line[index...]).trimmingCharacters(in: .whitespaces)
        // Strip an optional closing sequence of hashes: "## Title ##".
        while text.hasSuffix("#") {
            text.removeLast()
            text = text.trimmingCharacters(in: .whitespaces)
        }
        return MarkdownHeading(level: hashes, text: text)
    }
}

// MARK: - Builder

private final class DocumentBuilder {
    struct ProjectDraft {
        var title: String
        var line: Int
        var explicitShortTitle: String?
        var statusText: String?
        var updatedText: String?
        var preambleLines: [String] = []
        var sections: [SectionDraft] = []
    }

    struct SectionDraft {
        var title: String
        var line: Int
        var lines: [String] = []
    }

    let options: MarkdownProjectParser.Options
    let dateParser: MarkdownDateParser
    var diagnostics: [ParseDiagnostic] = []

    private var drafts: [ProjectDraft] = []
    private var sectionOpen = false

    init(options: MarkdownProjectParser.Options, dateParser: MarkdownDateParser) {
        self.options = options
        self.dateParser = dateParser
    }

    var hasProject: Bool { !drafts.isEmpty }
    var hasNoProject: Bool { drafts.isEmpty }

    func startProject(title: String, line: Int) {
        guard !title.isEmpty else { return }
        drafts.append(ProjectDraft(title: title, line: line))
        sectionOpen = false
    }

    func startSection(title: String, level: Int, line: Int) {
        guard drafts.last != nil else { return }
        drafts[drafts.count - 1].sections.append(SectionDraft(title: title, line: line))
        sectionOpen = true
    }

    func closeSection() {
        sectionOpen = false
    }

    func appendContent(_ line: String) {
        guard !drafts.isEmpty else { return }
        if sectionOpen, !drafts[drafts.count - 1].sections.isEmpty {
            drafts[drafts.count - 1].sections[drafts[drafts.count - 1].sections.count - 1].lines.append(line)
            return
        }
        // Between the project heading and its first section: metadata lives here.
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            drafts[drafts.count - 1].preambleLines.append(line)
            return
        }
        if let (key, value) = MetadataLine.parse(trimmed) {
            let normalizedKey = key.lowercased().replacingOccurrences(of: "：", with: "")
            if options.shortTitleKeys.contains(where: { $0.lowercased() == normalizedKey }) {
                drafts[drafts.count - 1].explicitShortTitle = value
                return
            }
            if options.statusKeys.contains(where: { $0.lowercased() == normalizedKey }) {
                drafts[drafts.count - 1].statusText = value
                return
            }
            if options.updatedKeys.contains(where: { $0.lowercased() == normalizedKey }) {
                drafts[drafts.count - 1].updatedText = value
                return
            }
        }
        drafts[drafts.count - 1].preambleLines.append(line)
    }

    func finish() -> [HudEXProject] {
        var taken = Set<String>()
        var projects: [HudEXProject] = []

        for (index, draft) in drafts.enumerated() {
            let id = StableID.unique(
                slug: StableID.slug(draft.title),
                taken: &taken,
                fallback: "project-\(index + 1)"
            )

            var sectionIDs = Set<String>()
            let sections: [ProjectSection] = draft.sections.map { section in
                let sectionID = StableID.unique(
                    slug: StableID.slug(section.title),
                    taken: &sectionIDs,
                    fallback: "section-\(index + 1)"
                )
                return ProjectSection(
                    id: sectionID,
                    title: section.title,
                    body: Self.trimBlankEdges(section.lines)
                )
            }

            let statusText = draft.statusText?.trimmingCharacters(in: .whitespaces)
            let updatedText = draft.updatedText?.trimmingCharacters(in: .whitespaces)
            var updatedAt: Date?
            if let updatedText, !updatedText.isEmpty {
                updatedAt = dateParser.parse(updatedText)
                if updatedAt == nil {
                    diagnostics.append(
                        ParseDiagnostic(
                            severity: .warning,
                            message: "无法解析更新日期 “\(updatedText)”（项目 \(draft.title)），已改用文件修改时间。",
                            line: draft.line
                        )
                    )
                }
            }

            let preamble = Self.trimBlankEdges(draft.preambleLines)
            let explicitShortTitle = draft.explicitShortTitle
                .flatMap { ShortTitle.sanitizeExplicit($0) }

            projects.append(
                HudEXProject(
                    id: id,
                    title: draft.title,
                    shortTitle: explicitShortTitle ?? ShortTitle.derive(from: draft.title),
                    hasExplicitShortTitle: explicitShortTitle != nil,
                    status: ProjectStatus.parse(statusText ?? ""),
                    statusText: statusText,
                    updatedAt: updatedAt,
                    updatedAtText: updatedText,
                    preamble: preamble.isEmpty ? nil : preamble,
                    sections: sections
                )
            )
        }

        return projects
    }

    private static func trimBlankEdges(_ lines: [String]) -> String {
        var copy = lines
        while let first = copy.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            copy.removeFirst()
        }
        while let last = copy.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            copy.removeLast()
        }
        return copy.joined(separator: "\n")
    }
}

/// A `key：value` line in a project preamble.
enum MetadataLine {
    static func parse(_ line: String) -> (key: String, value: String)? {
        // Full-width colon first (Chinese files), then ASCII colon.
        let separators: [Character] = ["：", ":"]
        guard let separatorIndex = line.firstIndex(where: { separators.contains($0) }) else {
            return nil
        }
        let key = String(line[line.startIndex..<separatorIndex]).trimmingCharacters(in: .whitespaces)
        let value = String(line[line.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, key.count <= 8 else { return nil }
        // Guard against URLs and prose that merely contains a colon.
        guard !key.contains("/"), !key.contains("//"), !value.hasPrefix("//") else { return nil }
        return (key, value)
    }
}

/// Parses the date formats people actually write in `HudEX.md`.
///
/// Formats are fixed, so the formatter objects are created once and reused —
/// parsing never allocates a `DateFormatter` per line.
public struct MarkdownDateParser: @unchecked Sendable {
    private static let patterns = [
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm",
        "yyyy/MM/dd HH:mm:ss",
        "yyyy/MM/dd HH:mm",
        "yyyy年M月d日 HH:mm",
        "yyyy年M月d日",
        "yyyy-MM-dd",
        "yyyy/MM/dd",
        "M月d日 HH:mm"
    ]

    private let formatters: [DateFormatter]

    public init(timeZone: TimeZone = .current, locale: Locale = Locale(identifier: "en_US_POSIX")) {
        formatters = Self.patterns.map { pattern in
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.dateFormat = pattern
            formatter.isLenient = false
            return formatter
        }
    }

    /// Returns `nil` when the text is not a recognised date.
    public func parse(_ text: String) -> Date? {
        var candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }
        candidate = candidate.replacingOccurrences(of: "T", with: "T")
        // Trailing notes such as "2026-09-12 16:30（初稿）".
        if let cut = candidate.firstIndex(where: { $0 == "（" || $0 == "(" || $0 == "—" }) {
            candidate = String(candidate[candidate.startIndex..<cut]).trimmingCharacters(in: .whitespaces)
        }
        for formatter in formatters {
            if let date = formatter.date(from: candidate) {
                return date
            }
        }
        return nil
    }
}
