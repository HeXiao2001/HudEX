import Foundation

/// The starter `HudEX.md` HudEX writes when the user has no file yet.
///
/// It doubles as the format reference: the dates are generated relative to
/// "now" so the three example tags show three different colours.
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

        return """
        # HudEX

        最近在推进的项目。这里只保留近期上下文：
        几个月以前的记录交给日记、Obsidian 和原始聊天。

        用法：`##` 是一个项目，`### 当前 / 下一步 / 最新对话 / 备注` 是项目内的小节。
        小节标题可以自由增加，HudEX 会把它们原样显示在“完整窗口”里。

        ---

        ## GeoRule

        短名：GR
        状态：进行中
        更新：\(stamp(daysAgo: 0, hour: 16, minute: 30))

        ### 当前

        2019-01、2019-02、2019-12 三期正式数据已经开始运行，初步结果正常。

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
        更新：\(stamp(daysAgo: 4, hour: 15, minute: 0))

        ### 当前

        标定阶段完成，正在整理第一轮结果。

        ### 下一步

        补齐缺失时段的数据，确认 OD 矩阵的对称性。

        ### 最新对话

        博士论文模型整理20260912

        ---

        ## 博士论文

        短名：PhD
        状态：进行中
        更新：\(stamp(daysAgo: 20, hour: 21, minute: 10))

        ### 当前

        第三章提纲已经写完，等待补充文献。

        ### 下一步

        把方法部分的推导补全。

        ### 最新对话

        论文结构讨论20260820
        """
    }

    /// Short hint shown in Settings when the file is missing.
    public static let missingFileHint = "还没有 HudEX.md。可以创建一个示例文件，然后按自己的项目改。"
}
