import DeskHUDCore
import SwiftUI

// MARK: - Writing-mode environment

private struct HUDVerticalTextKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True when the panel renders in vertical writing mode (side Dock with
    /// a narrow band). Text helpers switch from horizontal lines to upright
    /// CJK-style vertical stacking.
    var hudVerticalText: Bool {
        get { self[HUDVerticalTextKey.self] }
        set { self[HUDVerticalTextKey.self] = newValue }
    }
}

// MARK: - Adaptive text

/// Text that flips between horizontal lines and upright vertical stacking
/// based on the panel's writing mode. In vertical mode grapheme clusters
/// (CJK characters, emoji, digits, letters) stay upright and flow top-to-
/// bottom; when a column fills the available height, text continues in a new
/// column to the left — "two lines" become "two columns".
struct HUDText: View {
    var text: String
    var fontSize: Double
    var weight: Font.Weight = .regular
    var design: Font.Design = .rounded
    var color: Color = .white.opacity(0.85)

    @Environment(\.hudVerticalText) private var vertical

    var body: some View {
        if vertical {
            VerticalText(
                text: text,
                fontSize: fontSize,
                weight: weight,
                color: color
            )
        } else {
            Text(text)
                .font(.system(size: fontSize, weight: weight, design: design))
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }
}

// MARK: - Vertical text

struct VerticalText: View {
    let text: String
    let fontSize: Double
    let weight: Font.Weight
    let color: Color
    var lineSpacing: CGFloat = 2
    var columnSpacing: CGFloat = 4

    var body: some View {
        VerticalTextLayout(spacing: lineSpacing, columnSpacing: columnSpacing) {
            ForEach(Array(clusters.enumerated()), id: \.offset) { _, cluster in
                Text(cluster)
                    .font(.system(size: fontSize, weight: weight, design: .rounded))
                    .foregroundStyle(color)
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    /// Grapheme clusters without whitespace — spaces become column gaps.
    private var clusters: [String] {
        text.filter { !$0.isWhitespace }.map(String.init)
    }
}

/// Flows subviews top-to-bottom within a column; when the column height is
/// exhausted, continues in a new column to the left (traditional CJK order).
struct VerticalTextLayout: Layout {
    var spacing: CGFloat
    var columnSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let columns = arrange(sizes: sizes, columnHeight: proposal.height)
        let width = columns.reduce(CGFloat(0)) { total, column in
            total + column.maxWidth + (total > 0 ? columnSpacing : 0)
        }
        let height = columns.reduce(CGFloat(0)) { max($0, $1.usedHeight) }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let columns = arrange(sizes: sizes, columnHeight: proposal.height ?? bounds.height)
        // Columns flow right-to-left (traditional CJK order): first column at the right.
        var x = bounds.maxX
        for column in columns {
            var y = bounds.minY
            x -= column.maxWidth
            for index in column.indices {
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: .unspecified
                )
                y += sizes[index].height + spacing
            }
            x -= columnSpacing
        }
    }

    private struct Column {
        var indices: [Int] = []
        var maxWidth: CGFloat = 0
        var usedHeight: CGFloat = 0
    }

    private func arrange(sizes: [CGSize], columnHeight: CGFloat?) -> [Column] {
        guard !sizes.isEmpty else { return [] }
        var columns = [Column()]
        for (index, size) in sizes.enumerated() {
            let spacingBefore = columns[columns.count - 1].indices.isEmpty ? 0 : spacing
            if let columnHeight,
               !columns[columns.count - 1].indices.isEmpty,
               columns[columns.count - 1].usedHeight + spacingBefore + size.height > columnHeight {
                columns.append(Column())
            }
            let last = columns.count - 1
            columns[last].indices.append(index)
            columns[last].maxWidth = max(columns[last].maxWidth, size.width)
            columns[last].usedHeight += (columns[last].indices.count > 1 ? spacing : 0) + size.height
        }
        return columns
    }
}
