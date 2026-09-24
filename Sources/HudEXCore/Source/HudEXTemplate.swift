import Foundation

/// The starter `HudEX.md` HudEX writes when the user has no file yet.
///
/// The sample projects are deliberately ordinary — a work item, a report, a
/// reading list — because HudEX is about *keeping the recent context of a few
/// projects in sight*, which is not specific to any field. The blocks live in
/// the string tables, so a new file speaks the same language as the interface.
public enum HudEXTemplate {
    public static func markdown(now: Date = Date(), calendar: Calendar = .current) -> String {
        func stamp(daysAgo: Int, hour: Int, minute: Int) -> String {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = hour
            components.minute = minute
            let date = calendar.date(from: components) ?? day
            return TimestampFormatter.string(from: date)
        }

        let blocks = [
            L10n.t("sample.project1").replacingOccurrences(
                of: "{DATE}",
                with: stamp(daysAgo: 0, hour: 16, minute: 30)
            ),
            L10n.t("sample.project2").replacingOccurrences(
                of: "{DATE}",
                with: stamp(daysAgo: 4, hour: 15, minute: 0)
            ),
            L10n.t("sample.project3").replacingOccurrences(
                of: "{DATE}",
                with: stamp(daysAgo: 20, hour: 10, minute: 0)
            )
        ]

        return blocks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n\n---\n\n") + "\n"
    }

    /// Short hint shown in Settings when the file is missing.
    public static let missingFileHint = "还没有 HudEX.json。可以创建示例文件，然后编辑项目和提醒事项。"
}
