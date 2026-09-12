import Foundation

/// Canonical keys for the settings block at the bottom of `HudEX.md`.
///
/// The file is written by HudEX but meant to be edited by a person or an AI, so
/// every key is accepted in several spellings: HudEX always writes the
/// localised label, and always reads any alias back to the canonical key.
public enum SettingsKeys {
    public static let updated = "updated"
    public static let layoutMode = "layout.mode"
    public static let layoutEdge = "layout.edge"
    public static let layoutAnchor = "layout.anchor"
    public static let layoutOffset = "layout.offset"
    public static let tagWidth = "tag.width"
    public static let tagHeight = "tag.height"
    public static let tagFontSize = "tag.fontSize"
    public static let tagMaxCount = "tag.maxCount"
    public static let tagMaxPerSlot = "tag.maxPerSlot"
    public static let tagGap = "tag.gap"
    public static let tagCorner = "tag.corner"
    public static let tagStack = "tag.stack"
    public static let tagStackOverlap = "tag.stack.overlap"
    public static let tagStackRotation = "tag.stack.rotation"
    public static let tagStackStagger = "tag.stack.stagger"
    public static let dockThickness = "dock.thickness"
    public static let dockLength = "dock.length"
    public static let showTags = "show.tags"
    public static let showMenuBarIcon = "show.menuBarIcon"
    public static let showUpdatedTime = "show.updatedTime"
    public static let launchAtLogin = "launchAtLogin"
    public static let colorActiveDays = "color.activeDays"
    public static let colorAttentionDays = "color.attentionDays"
    public static let colorAgingDays = "color.agingDays"

    /// Order the writer emits the block in.
    public static let orderedKeys: [String] = [
        layoutMode, layoutEdge, layoutAnchor, layoutOffset,
        tagWidth, tagHeight, tagFontSize, tagMaxCount, tagMaxPerSlot,
        tagGap, tagCorner,
        tagStack, tagStackOverlap, tagStackRotation, tagStackStagger,
        dockThickness, dockLength,
        showTags, showMenuBarIcon, showUpdatedTime, launchAtLogin,
        colorActiveDays, colorAttentionDays, colorAgingDays
    ]

    /// Every accepted spelling of every key.
    private static let aliases: [String: String] = {
        var table: [String: String] = [:]
        func add(_ key: String, _ spellings: [String]) {
            for spelling in spellings {
                table[normalize(spelling)] = key
            }
        }
        add(layoutMode, ["布局", "布局模式", "layout", "mode", "layoutmode"])
        add(layoutEdge, ["边缘", "屏幕边", "边", "edge", "screen", "screenedge", "fixededge", "固定屏幕边"])
        add(layoutAnchor, ["对齐", "锚点", "起点", "anchor", "align", "alignment", "对齐方式"])
        add(layoutOffset, ["偏移", "位置偏移", "offset"])
        add(tagWidth, ["标签宽度", "宽度", "width", "tagwidth"])
        add(tagHeight, ["标签高度", "高度", "height", "tagheight"])
        add(tagFontSize, ["字号", "字体大小", "字体", "fontsize", "font", "labelsize", "标签字号"])
        add(tagMaxCount, ["最多标签数", "最多显示标签数", "最多显示", "最大数量", "maxtags", "maxcount"])
        add(tagMaxPerSlot, ["每个位置最多", "每侧最多", "maxperslot", "maxperside", "maxperposition", "每位置最多"])
        add(tagGap, ["dock间距", "间距", "与dock的间距", "gap", "dockgap", "gapfromdock"])
        add(tagCorner, ["转角留白", "边距", "屏幕转角留白", "corner", "cornerinset", "cornergap"])
        add(tagStack, ["叠放", "堆叠", "叠置", "stack", "stacked", "stackedtags"])
        add(tagStackOverlap, ["叠放重叠", "重叠", "重叠比例", "overlap", "stackoverlap"])
        add(tagStackRotation, ["叠放倾斜", "倾斜", "斜角", "rotation", "slant", "skew", "stackslant"])
        add(tagStackStagger, ["叠放错位", "错位", "层次", "stagger", "depth", "stacklayeroffset"])
        add(dockThickness, ["dock厚度", "厚度", "dockthickness"])
        add(dockLength, ["dock长度", "dock占用长度", "占用长度", "docklength", "dockoccupiedlength"])
        add(showTags, ["显示标签", "显示hudex标签", "showtags", "tags"])
        add(showMenuBarIcon, ["菜单栏图标", "显示菜单栏图标", "showmenubaricon", "menubar", "menubaricon"])
        add(showUpdatedTime, ["显示更新时间", "更新时间显示", "showupdatedtime"])
        add(launchAtLogin, ["开机启动", "开机自动启动", "开机时自动启动", "launchatlogin", "autostart"])
        add(colorActiveDays, ["绿色天数", "最近更新天数", "activedays", "greenthresholddays"])
        add(colorAttentionDays, ["黄色天数", "需要关注天数", "attentiondays", "yellowthresholddays"])
        add(colorAgingDays, ["橙色天数", "开始变旧天数", "agingdays", "orangethresholddays"])
        add(updated, ["更新", "最后更新", "更新时间", "updated", "updatedat", "lastupdate"])
        return table
    }()

    /// Lowercases and drops separators so `font-size`, `Font Size` and
    /// `字号` all land on the same key.
    public static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for separator in [" ", "\t", "-", "_", ".", "：", ":"] {
            text = text.replacingOccurrences(of: separator, with: "")
        }
        return text
    }

    /// Canonical key for any accepted spelling.
    ///
    /// Falls back to the labels HudEX itself writes (in every shipped
    /// language), so a block written in English is readable by a Chinese build
    /// and vice versa — the two directions can never drift apart.
    public static func canonical(_ raw: String) -> String? {
        let normalized = normalize(raw)
        if let key = aliases[normalized] { return key }
        return localizedLabels[normalized]
    }

    /// `normalize(label)` → canonical key, built from the string tables.
    private static let localizedLabels: [String: String] = {
        var table: [String: String] = [:]
        for language in L10n.supported {
            let strings = L10n.table(for: language)
            for key in orderedKeys {
                if let label = strings["settingsblock.label.\(key)"] {
                    table[normalize(label)] = key
                }
            }
        }
        return table
    }()

    /// True when the heading introduces the settings block.
    public static func isSettingsHeading(_ heading: String) -> Bool {
        let text = heading.lowercased()
        guard text.contains("hudex") else { return false }
        return text.contains("设置") || text.contains("配置") || text.contains("settings") || text.contains("config")
    }
}

/// Reads and writes the settings block.
public enum SettingsBlockFormat {
    /// Parses the text after the `# HudEX 设置` heading.
    public static func parse(_ raw: String, dateParser: MarkdownDateParser = MarkdownDateParser()) -> HudEXSettingsBlock {
        var entries: [HudEXSettingsBlock.Entry] = []
        var pendingGuide: String?
        var updatedAt: Date?
        var updatedAtText: String?

        let lines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                pendingGuide = nil
                continue
            }
            if trimmed.hasPrefix(">") {
                pendingGuide = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                continue
            }
            if trimmed.hasPrefix("#") || trimmed == "---" {
                pendingGuide = nil
                continue
            }
            guard let (label, value) = MetadataLine.parse(trimmed),
                  let key = SettingsKeys.canonical(label) else {
                pendingGuide = nil
                continue
            }

            if key == SettingsKeys.updated {
                updatedAtText = value
                updatedAt = dateParser.parse(value)
            } else {
                entries.append(
                    HudEXSettingsBlock.Entry(key: key, value: value, guide: pendingGuide)
                )
            }
            pendingGuide = nil
        }

        return HudEXSettingsBlock(
            entries: entries,
            updatedAt: updatedAt,
            updatedAtText: updatedAtText,
            raw: raw
        )
    }

    /// Builds the block text: one guide line, then one `label：value` line.
    public struct Field: Sendable, Equatable {
        public let key: String
        public let label: String
        public let guide: String
        public let value: String

        public init(key: String, label: String, guide: String, value: String) {
            self.key = key
            self.label = label
            self.guide = guide
            self.value = value
        }
    }

    public static func render(
        heading: String,
        intro: [String],
        updatedLabel: String,
        updatedGuide: String,
        updatedValue: String,
        fields: [Field]
    ) -> String {
        var lines: [String] = []
        lines.append("# \(heading)")
        lines.append("")
        for line in intro {
            lines.append("> \(line)")
        }
        lines.append("")
        lines.append("> \(updatedGuide)")
        lines.append("\(updatedLabel)：\(updatedValue)")
        lines.append("")

        for field in fields {
            lines.append("> \(field.guide)")
            lines.append("\(field.label)：\(field.value)")
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}
