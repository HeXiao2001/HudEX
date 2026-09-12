import XCTest
@testable import HudEXCore

/// The example documents that ship with the repository must keep parsing and
/// keep demonstrating the format (they are the first thing a new user sees).
final class ExamplesTests: XCTestCase {
    private func load(_ name: String) throws -> HudEXDocument {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("Examples/\(name)")
        let text = try String(contentsOf: url, encoding: .utf8)
        return MarkdownProjectParser().parse(text)
    }

    /// Both examples are ordinary, non-specialist projects and show every
    /// feature the format has.
    func testEnglishExample() throws {
        let document = try load("HudEX.md")
        XCTAssertEqual(document.projects.count, 4)
        XCTAssertTrue(document.diagnostics.filter { $0.severity != .info }.isEmpty)

        // `order: 1` sorts the report ahead of the website project.
        XCTAssertEqual(document.projects.map(\.title), [
            "Quarterly report", "Website redesign", "Reading list", "Home studio"
        ])
        XCTAssertEqual(document.projects.map(\.shortTitle), ["Q3", "WEB", "RL", "HS"])
        XCTAssertEqual(document.projects.first { $0.title == "Home studio" }?.colorOverride, "#4C6FA0")
        XCTAssertEqual(document.projects.first { $0.title == "Website redesign" }?.priority, .high)
        XCTAssertEqual(document.projects.first { $0.title == "Reading list" }?.status, .paused)
        XCTAssertEqual(document.projects.first { $0.title == "Home studio" }?.status, .done)
        XCTAssertEqual(
            document.projects.first { $0.title == "Quarterly report" }?.customSections.map(\.title),
            ["Data sources"]
        )
    }

    func testChineseExample() throws {
        let document = try load("HudEX.zh.md")
        XCTAssertEqual(document.projects.count, 4)
        XCTAssertEqual(document.projects.map(\.shortTitle), ["Q3", "WEB", "读书", "HS"])
        XCTAssertEqual(document.projects.first { $0.title == "读书清单" }?.status, .paused)
        XCTAssertEqual(
            document.projects.first { $0.title == "季度报告" }?.customSections.map(\.title),
            ["数据来源"]
        )
        XCTAssertEqual(document.projects.first { $0.title == "网站改版" }?.priority, .high)
    }

    func testTemplateIsValidInEveryLanguage() {
        // The starter file is localised; both variants must parse cleanly and
        // demonstrate metadata, ordering and a custom section.
        let english = MarkdownProjectParser().parse(HudEXTemplate.markdown())
        XCTAssertEqual(english.projects.count, 3)
        XCTAssertEqual(english.projects.map(\.shortTitle), ["Q3", "WEB", "RL"])
        XCTAssertEqual(english.projects.first?.title, "Quarterly report")
        XCTAssertEqual(english.projects.first?.sortOrder, 1)
        XCTAssertTrue(english.projects.allSatisfy { !$0.sections.isEmpty })
        XCTAssertTrue(
            english.projects.contains { !$0.customSections.isEmpty },
            "the template should show that extra ### sections are allowed"
        )
    }
}
