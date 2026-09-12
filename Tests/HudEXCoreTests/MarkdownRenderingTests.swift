import XCTest
@testable import HudEXCore

final class MarkdownRenderingTests: XCTestCase {
    func testBlockParsing() {
        let body = """
        第一段第一行
        第一段第二行

        - 项目一
        - 项目二

        1. 第一步
        2. 第二步

        > 引用

        收尾段落
        """
        let blocks = MarkdownBlockParser.blocks(from: body)
        XCTAssertEqual(blocks.count, 5)
        guard case .paragraph(let paragraph) = blocks[0] else { return XCTFail("expected paragraph") }
        XCTAssertEqual(paragraph, "第一段第一行\n第一段第二行")
        guard case .bulletList(let bullets) = blocks[1] else { return XCTFail("expected bullets") }
        XCTAssertEqual(bullets, ["项目一", "项目二"])
        guard case .numberedList(let numbers) = blocks[2] else { return XCTFail("expected numbers") }
        XCTAssertEqual(numbers.map(\.number), ["1", "2"])
        guard case .quote(let quote) = blocks[3] else { return XCTFail("expected quote") }
        XCTAssertEqual(quote, "引用")
        guard case .paragraph(let tail) = blocks[4] else { return XCTFail("expected paragraph") }
        XCTAssertEqual(tail, "收尾段落")
    }

    func testCodeBlockAndHeading() {
        let body = """
        #### 小标题

        ```
        code line
        ```
        """
        let blocks = MarkdownBlockParser.blocks(from: body)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0], .heading(level: 4, text: "小标题"))
        XCTAssertEqual(blocks[1], .codeBlock("code line"))
    }

    func testUnclosedCodeBlockIsNotLost() {
        let blocks = MarkdownBlockParser.blocks(from: "```\n未闭合")
        XCTAssertEqual(blocks, [.codeBlock("未闭合")])
    }

    func testInlineFormattingIsParsed() {
        let result = InlineMarkdown.attributed(from: "**粗体** 与 *斜体* 与 `code`")
        let text = String(result.attributed.characters)
        XCTAssertEqual(text, "粗体 与 斜体 与 code")

        var hasBold = false
        var hasCode = false
        for run in result.attributed.runs {
            if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true { hasBold = true }
            if run.inlinePresentationIntent?.contains(.code) == true { hasCode = true }
        }
        XCTAssertTrue(hasBold)
        XCTAssertTrue(hasCode)
    }

    func testWebLinksSurviveButOtherSchemesDoNot() {
        let result = InlineMarkdown.attributed(from: "[论文](https://example.com/a) 与 [本地](file:///etc/passwd)")
        let links = result.attributed.runs.compactMap { $0.link }
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.absoluteString, "https://example.com/a")
    }

    func testImagesAreStrippedAndAltTextKept() {
        let stripped = InlineMarkdown.stripUnsupportedSyntax("![实验图](image.png)")
        XCTAssertEqual(stripped, "实验图")

        let result = InlineMarkdown.attributed(from: "看图：![实验图](https://example.com/x.png)")
        XCTAssertEqual(String(result.attributed.characters), "看图：实验图")
        XCTAssertTrue(result.attributed.runs.allSatisfy { $0.link == nil })
    }

    func testEmbedsAndMediaTagsAreRemoved() {
        XCTAssertEqual(InlineMarkdown.stripUnsupportedSyntax("![[笔记]]"), "")
        XCTAssertEqual(InlineMarkdown.stripUnsupportedSyntax("<img src=\"x.png\">"), "")
        XCTAssertEqual(InlineMarkdown.stripUnsupportedSyntax("<video src=\"x.mp4\"></video>"), "")
    }

    func testPlainTextHelper() {
        XCTAssertEqual(InlineMarkdown.plainText(from: "**重要** `代码`"), "重要 代码")
    }

    func testMalformedMarkdownFallsBackToPlainText() {
        let result = InlineMarkdown.attributed(from: "未闭合的 [链接](https://example.com")
        XCTAssertFalse(String(result.attributed.characters).isEmpty)
    }
}

final class DocumentSourceTests: XCTestCase {
    func testFileSignatureDetectsContentChanges() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hudex-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("HudEX.md")
        try "# HudEX\n\n## A\n### 当前\nx\n".write(to: file, atomically: true, encoding: .utf8)

        let first = FileSignature.read(at: file)
        XCTAssertTrue(first.exists)

        let loader = MarkdownDocumentLoader()
        let initial = try loader.load(url: file, previous: nil).get()
        XCTAssertEqual(initial.document.projects.count, 1)

        // Unchanged file: the loader short-circuits without reading.
        let again = loader.load(url: file, previous: initial.signature)
        guard case .failure(.unchanged) = again else {
            return XCTFail("expected .unchanged when the signature matches")
        }

        // Content change (including size change).
        try "# HudEX\n\n## A\n### 当前\ny\n\n## B\n### 当前\nz\n".write(to: file, atomically: true, encoding: .utf8)
        let updated = try loader.load(url: file, previous: initial.signature).get()
        XCTAssertEqual(updated.document.projects.count, 2)
    }

    func testAtomicReplaceIsSeenByTheSignature() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hudex-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("HudEX.md")
        try "## A\n### 当前\nfirst\n".write(to: file, atomically: true, encoding: .utf8)
        let before = FileSignature.read(at: file)

        // Simulate editors and sync clients: write a temp file, rename over.
        let temp = directory.appendingPathComponent("HudEX.md.tmp")
        try "## A\n### 当前\nsecond, longer content\n".write(to: temp, atomically: true, encoding: .utf8)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: temp)

        let after = FileSignature.read(at: file)
        XCTAssertNotEqual(before, after)
    }

    func testMissingFileIsReportedNotThrown() {
        let loader = MarkdownDocumentLoader()
        let missing = URL(fileURLWithPath: "/definitely/not/here/HudEX.md")
        let result = loader.load(url: missing, previous: nil)
        guard case .failure(.fileMissing) = result else {
            return XCTFail("expected .fileMissing")
        }
    }

    func testEmptyFileProducesNoProjectsWithoutFailing() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hudex-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("HudEX.md")
        try "".write(to: file, atomically: true, encoding: .utf8)
        let loaded = try MarkdownDocumentLoader().load(url: file, previous: nil).get()
        XCTAssertTrue(loaded.document.projects.isEmpty)
    }

    func testDecodingFallsBackToLatin1() {
        let latin1 = "café".data(using: .isoLatin1)!
        XCTAssertEqual(MarkdownDocumentLoader.decode(latin1), "café")
    }

    func testUTF16IsOnlyDecodedWithAByteOrderMark() {
        let utf16 = "项目".data(using: .utf16)!
        XCTAssertEqual(MarkdownDocumentLoader.decode(utf16), "项目")

        // Pure ASCII bytes must never be mistaken for UTF-16.
        XCTAssertEqual(MarkdownDocumentLoader.decode("# A\n".data(using: .utf8)!), "# A\n")
    }

    func testGB18030Fallback() throws {
        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        let data = try XCTUnwrap("中文项目".data(using: gb18030))
        XCTAssertEqual(MarkdownDocumentLoader.decode(data), "中文项目")
    }

    func testStoredPathExpansion() {
        let url = SourceLocator.url(forStoredPath: "~/Documents/HudEX.md")
        XCTAssertTrue(url.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path))
        XCTAssertTrue(url.path.hasSuffix("Documents/HudEX.md"))
    }

    func testTemplateIsValid() {
        let document = MarkdownProjectParser().parse(HudEXTemplate.markdown())
        XCTAssertEqual(document.projects.count, 3)
        XCTAssertEqual(document.projects.map(\.shortTitle), ["GR", "OD", "PhD"])
        XCTAssertTrue(document.projects.allSatisfy { !$0.sections.isEmpty })
    }
}
