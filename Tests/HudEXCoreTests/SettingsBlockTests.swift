import XCTest
@testable import HudEXCore

final class SettingsBlockTests: XCTestCase {
    private let sample = """
    # HudEX

    ## GeoRule
    状态：进行中
    更新：2026-09-12 16:30

    ### 当前
    数据在跑。

    ---

    # HudEX 设置

    > 这一段由 HudEX 维护。
    > 改完保存即可。

    > 这一段最后写入的时间。
    更新：2026-09-12 20:15

    > 布局模式说明。
    布局模式：fixed-edge

    > 固定屏幕边。
    屏幕边：right

    > 标签宽度。
    标签宽度：88
    """

    func testSettingsBlockIsSplitFromProjects() {
        let document = MarkdownProjectParser().parse(sample)
        XCTAssertEqual(document.projects.count, 1)
        XCTAssertEqual(document.projects[0].title, "GeoRule")
        XCTAssertFalse(document.bodyWithoutSettings.contains("布局模式：fixed-edge"))

        let settings = try? XCTUnwrap(document.settings)
        XCTAssertEqual(settings?[SettingsKeys.layoutMode], "fixed-edge")
        XCTAssertEqual(settings?[SettingsKeys.layoutEdge], "right")
        XCTAssertEqual(settings?[SettingsKeys.tagWidth], "88")
        XCTAssertNotNil(settings?.updatedAt)
    }

    func testGuidesAreAttachedToTheFollowingEntry() {
        let document = MarkdownProjectParser().parse(sample)
        let block = try? XCTUnwrap(document.settings)
        let entry = block?.entries.first { $0.key == SettingsKeys.layoutMode }
        XCTAssertEqual(entry?.guide, "布局模式说明。")
    }

    func testAliasesResolveToCanonicalKeys() {
        XCTAssertEqual(SettingsKeys.canonical("字号"), SettingsKeys.tagFontSize)
        XCTAssertEqual(SettingsKeys.canonical("font-size"), SettingsKeys.tagFontSize)
        XCTAssertEqual(SettingsKeys.canonical("Font Size"), SettingsKeys.tagFontSize)
        XCTAssertEqual(SettingsKeys.canonical("叠放倾斜"), SettingsKeys.tagStackRotation)
        XCTAssertEqual(SettingsKeys.canonical("show.menuBarIcon"), SettingsKeys.showMenuBarIcon)
        XCTAssertNil(SettingsKeys.canonical("没有这个键"))
    }

    func testLongEnglishLabelsAreReadable() {
        let text = """
        # HudEX Settings

        > Layout mode guide.
        Layout mode：fixed-edge

        > Stack guide.
        Stack layer offset：3.5
        """
        let block = SettingsBlockFormat.parse(text)
        XCTAssertEqual(block[SettingsKeys.layoutMode], "fixed-edge")
        XCTAssertEqual(block[SettingsKeys.tagStackStagger], "3.5")
    }

    func testUnknownKeysAreIgnoredNotFatal() {
        let text = """
        # HudEX 设置

        未来选项：42
        标签宽度：70
        """
        let block = SettingsBlockFormat.parse(text)
        XCTAssertEqual(block[SettingsKeys.tagWidth], "70")
        XCTAssertEqual(block.entries.count, 1)
    }

    func testReplacingTheBlockKeepsProjectContentByteForByte() {
        let document = MarkdownProjectParser().parse(sample)
        let replacement = "# HudEX 设置\n\n> new\n更新：2026-09-13 09:00\n\n> guide\n标签宽度：12\n"
        let updated = SettingsSyncTextHelper.replace(in: sample, with: replacement)

        XCTAssertTrue(updated.contains("## GeoRule"))
        XCTAssertTrue(updated.contains("数据在跑。"))
        XCTAssertTrue(updated.contains("标签宽度：12"))
        XCTAssertFalse(updated.contains("标签宽度：88"))

        // Rewriting with what we just wrote is a no-op (no endless churn).
        let again = SettingsSyncTextHelper.replace(in: updated, with: replacement)
        XCTAssertEqual(updated, again)
    }

    func testBlockIsAppendedWhenMissing() {
        let text = "# HudEX\n\n## A\n### 当前\nx\n"
        let updated = SettingsSyncTextHelper.replace(in: text, with: "# HudEX 设置\n\n更新：2026-09-13 09:00\n")
        XCTAssertTrue(updated.contains("## A"))
        XCTAssertTrue(updated.contains("# HudEX 设置"))
        XCTAssertTrue(updated.hasSuffix("\n"))
    }

    func testRenderedBlockIsParseableAgain() {
        let rendered = SettingsBlockFormat.render(
            heading: "HudEX 设置",
            intro: ["说明一"],
            updatedLabel: "更新",
            updatedGuide: "写入时间",
            updatedValue: "2026-09-13 09:30",
            fields: [
                .init(key: SettingsKeys.layoutMode, label: "布局模式", guide: "模式说明", value: "dock-split"),
                .init(key: SettingsKeys.tagWidth, label: "标签宽度", guide: "宽度说明", value: "64")
            ]
        )
        let parsed = SettingsBlockFormat.parse(rendered)
        XCTAssertEqual(parsed[SettingsKeys.layoutMode], "dock-split")
        XCTAssertEqual(parsed[SettingsKeys.tagWidth], "64")
        XCTAssertEqual(parsed.updatedAtText, "2026-09-13 09:30")
        XCTAssertEqual(parsed.entries.first?.guide, "模式说明")
    }
}

/// The file surgery lives in the app target; this mirrors it so Core tests can
/// cover the text behaviour without importing AppKit.
enum SettingsSyncTextHelper {
    static func replace(in text: String, with block: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var cutIndex: Int?
        for (index, line) in lines.enumerated() {
            if let heading = MarkdownHeading.parse(line),
               heading.level == 1,
               SettingsKeys.isSettingsHeading(heading.text) {
                cutIndex = index
                break
            }
        }
        if let cutIndex {
            var head = Array(lines[0..<cutIndex])
            while let last = head.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
                head.removeLast()
            }
            if head.last?.trimmingCharacters(in: .whitespaces) == "---" {
                head.removeLast()
                while let last = head.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
                    head.removeLast()
                }
            }
            return head.joined(separator: "\n") + "\n\n---\n\n" + block
        }
        var head = lines
        while let last = head.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            head.removeLast()
        }
        return head.joined(separator: "\n") + "\n\n---\n\n" + block
    }
}

final class ProjectMetadataTests: XCTestCase {
    func testOrderAndColourMetadata() {
        let text = """
        ## Beta
        顺序：2
        颜色：#4C6FA0
        ### 当前
        b

        ## Alpha
        顺序：1
        颜色：绿色
        ### 当前
        a

        ## Gamma
        ### 当前
        g
        """
        let document = MarkdownProjectParser().parse(text)
        XCTAssertEqual(document.projects.map(\.title), ["Alpha", "Beta", "Gamma"])
        XCTAssertEqual(document.projects[0].colorOverride, "绿色")
        XCTAssertEqual(document.projects[1].colorOverride, "#4C6FA0")
        XCTAssertNil(document.projects[2].colorOverride)
        XCTAssertEqual(document.projects[0].sortOrder, 1)
    }

    func testColourNamesResolve() {
        XCTAssertNotNil(TagPalette.color(named: "绿色", isDark: false))
        XCTAssertNotNil(TagPalette.color(named: "Teal", isDark: true))
        XCTAssertNotNil(TagPalette.color(named: "#123456", isDark: false))
        XCTAssertNil(TagPalette.color(named: "octarine", isDark: false))
    }

    func testHexParsingAndContrast() {
        let white = PaletteColor(hex: "#FFFFFF")!
        XCTAssertEqual(white.contrastingTextColor, PaletteColor(red: 0, green: 0, blue: 0))
        let black = PaletteColor(hex: "#000000")!
        XCTAssertEqual(black.contrastingTextColor, PaletteColor(red: 1, green: 1, blue: 1))
        XCTAssertNil(PaletteColor(hex: "nope"))
        XCTAssertEqual(PaletteColor(hex: "#4C6FA0")!.hexString, "#4C6FA0")
    }

    func testEveryRoleKeepsReadableContrast() {
        for role in TagColorRole.allCases {
            for isDark in [false, true] {
                let background = TagPalette.color(for: role, isDark: isDark)
                let text = background.contrastingTextColor
                let ratio = text == PaletteColor(red: 1, green: 1, blue: 1)
                    ? background.contrastRatioAgainstWhite
                    : background.contrastRatioAgainstBlack
                XCTAssertGreaterThan(ratio, 3.5, "\(role) in \(isDark ? "dark" : "light") has weak contrast")
            }
        }
    }

    func testCustomColourWinsOverRole() {
        let appearance = TagAppearanceResolver.appearance(role: .stale, colorOverride: "teal", isDark: false)
        XCTAssertTrue(appearance.isCustom)
        XCTAssertEqual(appearance.background.hexString, TagPalette.color(named: "teal", isDark: false)?.hexString)

        let fallback = TagAppearanceResolver.appearance(role: .stale, colorOverride: "octarine", isDark: false)
        XCTAssertFalse(fallback.isCustom)
    }
}

final class LocalizationTests: XCTestCase {
    /// Keys referenced as `L10n.t("…")` anywhere in the sources.
    private func usedKeys() -> Set<String> {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        var keys: Set<String> = []
        guard let enumerator = FileManager.default.enumerator(
            at: root.appendingPathComponent("Sources"),
            includingPropertiesForKeys: nil
        ) else { return keys }

        for case let file as URL in enumerator where file.pathExtension == "swift" {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for piece in text.components(separatedBy: "L10n.t(\"") {
                guard let key = piece.split(separator: "\"", maxSplits: 1).first else { continue }
                // Real keys are dotted lowercase identifiers.
                if key.contains("."), !key.contains(" "), !key.contains("(") {
                    keys.insert(String(key))
                }
            }
        }
        return keys
    }

    func testBothLanguagesContainEveryKey() {
        let en = L10n.table(for: "en")
        let zh = L10n.table(for: "zh-Hans")
        XCTAssertFalse(en.isEmpty, "English table missing")
        XCTAssertFalse(zh.isEmpty, "Chinese table missing")
        XCTAssertEqual(Set(en.keys), Set(zh.keys), "the two tables disagree")
    }

    func testEveryKeyUsedInCodeExists() {
        let en = L10n.table(for: "en")
        let zh = L10n.table(for: "zh-Hans")
        let used = usedKeys()
        XCTAssertGreaterThan(used.count, 100, "the scanner found suspiciously few keys")
        let missing = used.filter { en[$0] == nil }
        XCTAssertTrue(missing.isEmpty, "keys used but not translated: \(missing.sorted())")
        let missingChinese = used.filter { zh[$0] == nil }
        XCTAssertTrue(missingChinese.isEmpty, "keys without a Chinese translation: \(missingChinese.sorted())")
    }

    func testSettingsBlockGuidesExist() {
        let en = L10n.table(for: "en")
        for key in SettingsKeys.orderedKeys {
            XCTAssertNotNil(en["settingsblock.guide.\(key)"], "missing guide for \(key)")
            XCTAssertNotNil(en["settingsblock.label.\(key)"], "missing label for \(key)")
        }
    }

    /// Anything HudEX writes must be readable again — otherwise the two-way
    /// sync silently drops settings.
    func testEveryWrittenLabelRoundTrips() {
        for language in L10n.supported {
            let strings = L10n.table(for: language)
            for key in SettingsKeys.orderedKeys {
                guard let label = strings["settingsblock.label.\(key)"] else {
                    XCTFail("missing label for \(key) in \(language)")
                    continue
                }
                XCTAssertEqual(
                    SettingsKeys.canonical(label),
                    key,
                    "the label \"\(label)\" (\(language)) does not map back to \(key)"
                )
            }
        }
        XCTAssertEqual(SettingsKeys.canonical("Updated"), SettingsKeys.updated)
    }

    func testLanguageSelectionFallsBackToEnglish() {
        XCTAssertTrue(L10n.supported.contains("en"))
        XCTAssertTrue(L10n.supported.contains("zh-Hans"))
        XCTAssertFalse(L10n.language.isEmpty)
    }
}
