import XCTest
@testable import HudEXCore

final class TagColorPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_787_000_000)   // fixed reference

    private func date(daysAgo: Int) -> Date {
        now.addingTimeInterval(-Double(daysAgo) * 86_400)
    }

    func testAgeThresholds() {
        let thresholds = TagColorThresholds.default
        XCTAssertEqual(role(days: 0, thresholds: thresholds), .active)
        XCTAssertEqual(role(days: 2, thresholds: thresholds), .active)
        XCTAssertEqual(role(days: 3, thresholds: thresholds), .attention)
        XCTAssertEqual(role(days: 6, thresholds: thresholds), .attention)
        XCTAssertEqual(role(days: 7, thresholds: thresholds), .aging)
        XCTAssertEqual(role(days: 13, thresholds: thresholds), .aging)
        XCTAssertEqual(role(days: 14, thresholds: thresholds), .stale)
        XCTAssertEqual(role(days: 400, thresholds: thresholds), .stale)
    }

    func testStatusOverridesAge() {
        XCTAssertEqual(
            TagColorPolicy.role(status: .paused, updatedAt: now, now: now),
            .paused
        )
        XCTAssertEqual(
            TagColorPolicy.role(status: .archived, updatedAt: now, now: now),
            .archived
        )
        XCTAssertEqual(
            TagColorPolicy.role(status: .done, updatedAt: now, now: now),
            .archived
        )
    }

    func testMissingDateIsStale() {
        XCTAssertEqual(TagColorPolicy.role(status: .active, updatedAt: nil, now: now), .stale)
    }

    func testFutureDatesAreTreatedAsFresh() {
        let future = now.addingTimeInterval(86_400)
        XCTAssertEqual(TagColorPolicy.role(status: .active, updatedAt: future, now: now), .active)
    }

    func testCustomThresholds() {
        let thresholds = TagColorThresholds(activeThroughDays: 10, attentionThroughDays: 20, agingThroughDays: 30)
        XCTAssertEqual(role(days: 10, thresholds: thresholds), .active)
        XCTAssertEqual(role(days: 15, thresholds: thresholds), .attention)
        XCTAssertEqual(role(days: 25, thresholds: thresholds), .aging)
        XCTAssertEqual(role(days: 31, thresholds: thresholds), .stale)
    }

    func testThresholdsSelfRepairWhenOutOfOrder() {
        let thresholds = TagColorThresholds(activeThroughDays: 10, attentionThroughDays: 4, agingThroughDays: 2)
        XCTAssertEqual(thresholds.attentionThroughDays, 10)
        XCTAssertEqual(thresholds.agingThroughDays, 10)
    }

    func testRelativeAgeStrings() {
        XCTAssertEqual(RelativeAgeFormatter.string(from: now.addingTimeInterval(-30), now: now), "刚刚")
        XCTAssertEqual(RelativeAgeFormatter.string(from: now.addingTimeInterval(-600), now: now), "10 分钟前")
        XCTAssertEqual(RelativeAgeFormatter.string(from: now.addingTimeInterval(-7200), now: now), "2 小时前")
        XCTAssertTrue(RelativeAgeFormatter.string(from: date(daysAgo: 3), now: now).hasSuffix("天前"))
    }

    func testTimestampFormatting() {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 12
        components.hour = 16
        components.minute = 30
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let date = calendar.date(from: components)!
        XCTAssertEqual(TimestampFormatter.string(from: date), "2026-09-12 16:30")
    }

    private func role(days: Int, thresholds: TagColorThresholds) -> TagColorRole {
        TagColorPolicy.role(
            status: .active,
            updatedAt: date(daysAgo: days),
            now: now,
            thresholds: thresholds
        )
    }
}

final class ShortTitleTests: XCTestCase {
    func testCamelCaseInitials() {
        XCTAssertEqual(ShortTitle.derive(from: "GeoRule"), "GR")
    }

    func testWordInitials() {
        XCTAssertEqual(ShortTitle.derive(from: "Model Training"), "MT")
        XCTAssertEqual(ShortTitle.derive(from: "alpha-beta"), "AB")
    }

    func testAcronymsAreKept() {
        XCTAssertEqual(ShortTitle.derive(from: "OD"), "OD")
        XCTAssertEqual(ShortTitle.derive(from: "PhD"), "PHD")
    }

    func testChineseTitlesUseLeadingGlyphs() {
        XCTAssertEqual(ShortTitle.derive(from: "博士论文"), "博士")
        XCTAssertEqual(ShortTitle.derive(from: "实验数据整理"), "实验")
    }

    func testPlainWordsAreTruncated() {
        XCTAssertEqual(ShortTitle.derive(from: "Zotero"), "ZOT")
        XCTAssertEqual(ShortTitle.derive(from: ""), "?")
    }

    func testExplicitShortTitleWins() {
        XCTAssertEqual(ShortTitle.resolve(explicit: "GR", title: "GeoRule"), "GR")
        XCTAssertEqual(ShortTitle.resolve(explicit: "  ", title: "GeoRule"), "GR")
        XCTAssertEqual(ShortTitle.resolve(explicit: "ABCDE", title: "GeoRule"), "ABCD")
        XCTAssertEqual(ShortTitle.resolve(explicit: nil, title: "GeoRule"), "GR")
    }

    func testSlugStability() {
        XCTAssertEqual(StableID.slug("GeoRule"), "georule")
        XCTAssertEqual(StableID.slug("博士论文 2026"), "博士论文-2026")
        XCTAssertEqual(StableID.slug("— —"), "")
    }
}
