import Foundation
import HudEXCore

/// Two-way sync between the app's preferences and the settings block at the
/// bottom of `HudEX.md`.
///
/// * Reading: every key present in the file is applied to `Preferences`, so a
///   person — or an AI — can change the layout, colours, thresholds and counts
///   by editing text.
/// * Writing: whenever a preference changes, the block is rewritten (debounced,
///   atomically) with fresh guide lines, so the file always documents itself.
///
/// The file is only ever touched from the marker heading down; project content
/// above it is preserved byte for byte.
@MainActor
final class SettingsSync {
    private let preferences: Preferences
    private var pendingWrite: DispatchWorkItem?
    private var lastAppliedRaw: String?

    /// Set by the controller so the UI can show when the block was written.
    private(set) var lastWriteAt: Date?

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    // MARK: - Reading

    /// Applies the settings block of a freshly parsed document.
    ///
    /// Returns `true` when something actually changed.
    @discardableResult
    func apply(from document: HudEXDocument) -> Bool {
        guard let block = document.settings, !block.isEmpty else { return false }
        lastAppliedRaw = block.raw
        var changed = false

        func value(_ key: String) -> String? {
            block[key]?.trimmingCharacters(in: .whitespaces)
        }
        func bool(_ key: String) -> Bool? {
            guard let raw = value(key)?.lowercased() else { return nil }
            switch raw {
            case "true", "yes", "on", "1", "是", "开", "打开": return true
            case "false", "no", "off", "0", "否", "关", "关闭": return false
            default: return nil
            }
        }
        func number(_ key: String) -> Double? {
            guard let raw = value(key) else { return nil }
            return Double(raw)
        }
        func integer(_ key: String) -> Int? {
            guard let raw = value(key) else { return nil }
            if let int = Int(raw) { return int }
            return Double(raw).map { Int($0) }
        }

        func set<T: Equatable>(_ key: String, _ transform: (String) -> T?, into path: ReferenceWritableKeyPath<Preferences, T>) {
            guard let raw = value(key), let parsed = transform(raw) else { return }
            if preferences[keyPath: path] != parsed {
                preferences[keyPath: path] = parsed
                changed = true
            }
        }

        set(SettingsKeys.appearanceStyle, { AppearanceStyle.parse($0) }, into: \.appearanceStyle)
        set(SettingsKeys.layoutMode, { LayoutMode.Kind(rawValue: $0.lowercased()) }, into: \.layoutKind)
        set(SettingsKeys.layoutEdge, { DockEdge(rawValue: $0.lowercased()) }, into: \.layoutEdge)
        set(SettingsKeys.layoutAnchor, { LayoutMode.Anchor(rawValue: $0.lowercased()) }, into: \.layoutAnchor)
        if let value = number(SettingsKeys.layoutOffset), preferences.layoutOffset != value {
            preferences.layoutOffset = value
            changed = true
        }
        if let value = number(SettingsKeys.tagWidth), preferences.tabProtrusion != value {
            preferences.tabProtrusion = value
            changed = true
        }
        if let value = number(SettingsKeys.tagHeight), preferences.tabLength != value {
            preferences.tabLength = value
            changed = true
        }
        if let value = number(SettingsKeys.tagFontSize), preferences.fontSize != value {
            preferences.fontSize = value
            changed = true
        }
        if let value = integer(SettingsKeys.tagMaxCount), preferences.maxTags != value {
            preferences.maxTags = value
            changed = true
        }
        if let value = integer(SettingsKeys.tagMaxPerSlot), preferences.maxTagsPerSlot != value {
            preferences.maxTagsPerSlot = value
            changed = true
        }
        if let value = number(SettingsKeys.tagGap), preferences.edgeGap != value {
            preferences.edgeGap = value
            changed = true
        }
        if let value = number(SettingsKeys.tagCorner), preferences.cornerInset != value {
            preferences.cornerInset = value
            changed = true
        }
        if let value = bool(SettingsKeys.tagStack), preferences.stackEnabled != value {
            preferences.stackEnabled = value
            changed = true
        }
        if let value = number(SettingsKeys.tagStackOverlap), preferences.stackOverlap != value {
            preferences.stackOverlap = value
            changed = true
        }
        if let value = number(SettingsKeys.tagStackRotation), preferences.stackRotation != value {
            preferences.stackRotation = value
            changed = true
        }
        if let value = number(SettingsKeys.tagStackStagger), preferences.stackStagger != value {
            preferences.stackStagger = value
            changed = true
        }
        if let value = number(SettingsKeys.dockThickness), preferences.dockThicknessOverride != value {
            preferences.dockThicknessOverride = value
            changed = true
        }
        if let value = number(SettingsKeys.dockLength), preferences.dockLengthOverride != value {
            preferences.dockLengthOverride = value
            changed = true
        }
        if let value = bool(SettingsKeys.showTags), preferences.showTags != value {
            preferences.showTags = value
            changed = true
        }
        if let value = bool(SettingsKeys.showMenuBarIcon), preferences.showMenuBarIcon != value {
            preferences.showMenuBarIcon = value
            changed = true
        }
        if let value = bool(SettingsKeys.showUpdatedTime), preferences.showUpdatedTime != value {
            preferences.showUpdatedTime = value
            changed = true
        }
        if let value = integer(SettingsKeys.colorActiveDays), preferences.thresholdActive != value {
            preferences.thresholdActive = value
            changed = true
        }
        if let value = integer(SettingsKeys.colorAttentionDays), preferences.thresholdAttention != value {
            preferences.thresholdAttention = value
            changed = true
        }
        if let value = integer(SettingsKeys.colorAgingDays), preferences.thresholdAging != value {
            preferences.thresholdAging = value
            changed = true
        }

        return changed
    }

    // MARK: - Writing

    /// Schedules a write-back after the user stops changing settings.
    func scheduleWrite(to url: URL) {
        guard preferences.settingsWriteBack else { return }
        pendingWrite?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.writeNow(to: url)
        }
        pendingWrite = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    /// Cancels a pending write-back (used when the file itself just changed).
    func cancelPendingWrite() {
        pendingWrite?.cancel()
        pendingWrite = nil
    }

    /// Rewrites the settings block immediately.
    @discardableResult
    func writeNow(to url: URL) -> Bool {
        pendingWrite?.cancel()
        pendingWrite = nil
        guard preferences.settingsWriteBack else { return false }
        guard let existing = try? String(contentsOf: url, encoding: .utf8) else { return false }

        let rendered = renderBlock(now: Date())
        let updated = Self.replacingSettingsBlock(in: existing, with: rendered)
        guard updated != existing else { return false }

        do {
            try Self.writeAtomically(updated, to: url)
            lastWriteAt = Date()
            lastAppliedRaw = rendered
            Log.markdown.info("settings block written to \(url.lastPathComponent, privacy: .public)")
            return true
        } catch {
            Log.markdown.error("settings write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// The exact text of the block as it would be written now.
    func renderBlock(now: Date = Date()) -> String {
        let updatedValue = TimestampFormatter.string(from: now)
        var fields: [SettingsBlockFormat.Field] = []

        func field(_ key: String, _ value: String) {
            let label = L10n.t("settingsblock.label.\(key)")
            let guide = L10n.t("settingsblock.guide.\(key)")
            fields.append(
                SettingsBlockFormat.Field(
                    key: key,
                    label: label == "settingsblock.label.\(key)" ? key : label,
                    guide: guide,
                    value: value
                )
            )
        }

        field(SettingsKeys.appearanceStyle, preferences.appearanceStyle.rawValue)
        field(SettingsKeys.layoutMode, preferences.layoutKind.rawValue)
        field(SettingsKeys.layoutEdge, preferences.layoutEdge.rawValue)
        field(SettingsKeys.layoutAnchor, preferences.layoutAnchor.rawValue)
        field(SettingsKeys.layoutOffset, Self.number(preferences.layoutOffset))
        field(SettingsKeys.tagWidth, Self.number(preferences.tabProtrusion))
        field(SettingsKeys.tagHeight, Self.number(preferences.tabLength))
        field(SettingsKeys.tagFontSize, Self.number(preferences.fontSize))
        field(SettingsKeys.tagMaxCount, "\(preferences.maxTags)")
        field(SettingsKeys.tagMaxPerSlot, "\(preferences.maxTagsPerSlot)")
        field(SettingsKeys.tagGap, Self.number(preferences.edgeGap))
        field(SettingsKeys.tagCorner, Self.number(preferences.cornerInset))
        field(SettingsKeys.tagStack, preferences.stackEnabled ? "true" : "false")
        field(SettingsKeys.tagStackOverlap, Self.number(preferences.stackOverlap))
        field(SettingsKeys.tagStackRotation, Self.number(preferences.stackRotation))
        field(SettingsKeys.tagStackStagger, Self.number(preferences.stackStagger))
        field(SettingsKeys.dockThickness, Self.number(preferences.dockThicknessOverride))
        field(SettingsKeys.dockLength, Self.number(preferences.dockLengthOverride))
        field(SettingsKeys.showTags, preferences.showTags ? "true" : "false")
        field(SettingsKeys.showMenuBarIcon, preferences.showMenuBarIcon ? "true" : "false")
        field(SettingsKeys.showUpdatedTime, preferences.showUpdatedTime ? "true" : "false")
        field(SettingsKeys.launchAtLogin, LaunchAtLoginService.shared.isEnabled ? "true" : "false")
        field(SettingsKeys.colorActiveDays, "\(preferences.thresholdActive)")
        field(SettingsKeys.colorAttentionDays, "\(preferences.thresholdAttention)")
        field(SettingsKeys.colorAgingDays, "\(preferences.thresholdAging)")

        var rendered = SettingsBlockFormat.render(
            heading: L10n.t("settingsblock.heading"),
            intro: [L10n.t("settingsblock.intro.1"), L10n.t("settingsblock.intro.2")],
            updatedLabel: L10n.t("settingsblock.updatedLabel"),
            updatedGuide: L10n.t("settingsblock.updatedGuide"),
            updatedValue: updatedValue,
            fields: fields
        )

        // Per-project options are documented here too: this is the part an AI
        // reads when it wants to reorder or recolour tags.
        rendered += """
        \(L10n.t("settingsblock.project.guide.title"))

        > \(L10n.t("settingsblock.guide.project.order"))
        > \(L10n.t("settingsblock.guide.project.color"))
        > \(L10n.t("settingsblock.guide.project.priority"))

        """
        return rendered
    }

    // MARK: - File surgery

    /// Replaces everything from the settings heading down, keeping the rest.
    static func replacingSettingsBlock(in text: String, with block: String) -> String {
        SettingsBlockSurgery.replace(in: text, with: block)
    }

    /// Writes through a temporary file so OneDrive and editors only ever see a
    /// complete file.
    static func writeAtomically(_ text: String, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".hudex-\(UUID().uuidString).tmp")
        try text.write(to: temporary, atomically: true, encoding: .utf8)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    }

    private static func number(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}

/// Pure text surgery, kept apart from the file I/O so it can be unit tested.
public enum SettingsBlockSurgery {
    public static func replace(in text: String, with block: String) -> String {
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

        let separator = "---"
        if let cutIndex {
            var head = Array(lines[0..<cutIndex])
            while let last = head.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
                head.removeLast()
            }
            if head.last?.trimmingCharacters(in: .whitespaces) == separator {
                head.removeLast()
                while let last = head.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
                    head.removeLast()
                }
            }
            return head.joined(separator: "\n") + "\n\n" + separator + "\n\n" + block
        }

        var head = lines
        while let last = head.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            head.removeLast()
        }
        return head.joined(separator: "\n") + "\n\n" + separator + "\n\n" + block
    }
}
