import XCTest
@testable import HudEXCore

final class MarkdownProjectParserTests: XCTestCase {
    private let parser = MarkdownProjectParser()

    private let sample = """
    # HudEX

    最近的上下文。

    ## GeoRule

    短名：GR
    状态：进行中
    更新：2026-09-12 16:30

    ### 当前

    2019-01、2019-02、2019-12 三期正式数据已经开始运行，
    初步结果正常。

    ### 下一步

    检查规则稳定性、K 数量和 h 是否触及搜索边界。

    ### 最新对话

    模型发展总结20260907

    ### 备注

    - 需要整理实验脚本最新版本
    - 后续考虑加入 baseline-2

    ---

    ## OD

    短名：OD
    状态：进行中
    更新：2026-09-12 15:00

    ### 当前

    标定完成。
    """

    func testParsesProjectsMetadataAndSections() {
        let document = parser.parse(sample)

        XCTAssertEqual(document.title, "HudEX")
        XCTAssertEqual(document.projects.count, 2)

        let geoRule = document.projects[0]
        XCTAssertEqual(geoRule.title, "GeoRule")
        XCTAssertEqual(geoRule.shortTitle, "GR")
        XCTAssertTrue(geoRule.hasExplicitShortTitle)
        XCTAssertEqual(geoRule.status, .active)
        XCTAssertEqual(geoRule.statusText, "进行中")
        XCTAssertNotNil(geoRule.updatedAt)
        XCTAssertEqual(geoRule.sections.count, 4)
        XCTAssertTrue(geoRule.currentSection?.body.contains("2019-01") == true)
        XCTAssertEqual(geoRule.nextSection?.body, "检查规则稳定性、K 数量和 h 是否触及搜索边界。")
        XCTAssertEqual(geoRule.latestConversationSection?.body, "模型发展总结20260907")
        XCTAssertEqual(geoRule.notesSection?.body, "- 需要整理实验脚本最新版本\n- 后续考虑加入 baseline-2")
        XCTAssertNil(geoRule.preamble)

        let od = document.projects[1]
        XCTAssertEqual(od.title, "OD")
        XCTAssertEqual(od.shortTitle, "OD")
    }

    func testCustomSectionHeadingsAreKept() {
        let text = """
        ## 项目A
        状态：进行中

        ### 当前
        x

        ### 数据来源
        y

        ### 实验记录 2026
        z
        """
        let document = parser.parse(text)
        let project = try? XCTUnwrap(document.projects.first)
        XCTAssertEqual(project?.sections.map(\.title), ["当前", "数据来源", "实验记录 2026"])
        XCTAssertEqual(project?.customSections.map(\.title), ["数据来源", "实验记录 2026"])
    }

    func testMissingSectionsDoNotFail() {
        let text = """
        ## 只有名字的项目

        ### 当前
        只写了当前。
        """
        let document = parser.parse(text)
        XCTAssertEqual(document.projects.count, 1)
        XCTAssertNil(document.projects[0].nextSection)
        XCTAssertNil(document.projects[0].latestConversationSection)
    }

    func testUnparsableDateKeepsRawTextAndWarns() {
        let text = """
        ## 项目
        更新：最近几天

        ### 当前
        x
        """
        let document = parser.parse(text)
        XCTAssertNil(document.projects[0].updatedAt)
        XCTAssertEqual(document.projects[0].updatedAtText, "最近几天")
        XCTAssertTrue(document.diagnostics.contains { $0.severity == .warning })
    }

    func testEmptyFileYieldsDiagnosticNotCrash() {
        let document = parser.parse("")
        XCTAssertTrue(document.projects.isEmpty)
        XCTAssertFalse(document.diagnostics.isEmpty)
    }

    func testBrokenMarkdownStillProducesProjects() {
        let text = """
        ## 项目一
        ###
        ### 当前
        |表格|错乱|
        ```
        未闭合的代码块
        """
        let document = parser.parse(text)
        XCTAssertEqual(document.projects.count, 1)
        XCTAssertEqual(document.projects[0].title, "项目一")
    }

    func testDuplicateTitlesGetStableUniqueIDs() {
        let text = """
        ## 项目
        ### 当前
        a

        ## 项目
        ### 当前
        b
        """
        let document = parser.parse(text)
        XCTAssertEqual(document.projects.count, 2)
        XCTAssertEqual(document.projects[0].id, "项目")
        XCTAssertEqual(document.projects[1].id, "项目-2")

        // Re-parsing the same text must produce the same ids.
        let again = parser.parse(text)
        XCTAssertEqual(document.projects.map(\.id), again.projects.map(\.id))
    }

    func testShortNameIsDerivedWhenMissing() {
        let text = """
        ## GeoRule
        ### 当前
        a

        ## 博士论文
        ### 当前
        b
        """
        let document = parser.parse(text)
        XCTAssertEqual(document.projects[0].shortTitle, "GR")
        XCTAssertFalse(document.projects[0].hasExplicitShortTitle)
        XCTAssertEqual(document.projects[1].shortTitle, "博士")
    }

    func testDateFormats() {
        let dateParser = MarkdownDateParser(timeZone: TimeZone(identifier: "Asia/Shanghai")!)
        XCTAssertNotNil(dateParser.parse("2026-09-12 16:30"))
        XCTAssertNotNil(dateParser.parse("2026-09-12"))
        XCTAssertNotNil(dateParser.parse("2026-09-12T16:30:00"))
        XCTAssertNotNil(dateParser.parse("2026/09/12 16:30"))
        XCTAssertNotNil(dateParser.parse("2026年9月12日"))
        XCTAssertNotNil(dateParser.parse("2026-09-12 16:30（初稿）"))
        XCTAssertNil(dateParser.parse("昨天"))
        XCTAssertNil(dateParser.parse(""))
    }

    func testPreambleProseIsPreserved() {
        let text = """
        ## 项目
        这是一段没有冒号的说明。

        ### 当前
        x
        """
        let document = parser.parse(text)
        XCTAssertEqual(document.projects[0].preamble, "这是一段没有冒号的说明。")
    }

    func testStatusAliases() {
        XCTAssertEqual(ProjectStatus.parse("进行中"), .active)
        XCTAssertEqual(ProjectStatus.parse("paused"), .paused)
        XCTAssertEqual(ProjectStatus.parse("归档"), .archived)
        XCTAssertEqual(ProjectStatus.parse("已完成"), .done)
        XCTAssertEqual(ProjectStatus.parse("进行中（主攻）"), .active)
        XCTAssertEqual(ProjectStatus.parse("随便写的"), .unknown)
        XCTAssertEqual(ProjectStatus.parse(""), .unknown)
    }
}
