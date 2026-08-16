import AppKit
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
/// (CJK characters, emoji) stay upright and flow top-to-bottom; Latin runs
/// (letters, digits, times) rotate 90° clockwise as a block — the standard
/// CJK vertical-typography treatment. When a column fills the available
/// height, text continues in a new column to the left — "two lines" become
/// "two columns".
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
    /// Gentle vertical justification: extra per-gap spacing used to spread a
    /// short column so it doesn't leave the panel bottom empty.
    var maxJustifySpacing: CGFloat = 12

    var body: some View {
        VerticalTextLayout(
            spacing: lineSpacing,
            columnSpacing: columnSpacing,
            justifyHeight: true,
            maxJustifySpacing: maxJustifySpacing
        ) {
            ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                switch element {
                case .upright(let cluster):
                    Text(cluster)
                        .font(.system(size: fontSize, weight: weight, design: .rounded))
                        .foregroundStyle(color)
                        .fixedSize()
                case .rotatedRun(let run):
                    RotatedRun(text: run, fontSize: fontSize, weight: weight, color: color)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private enum VElement {
        case upright(String)
        case rotatedRun(String)
    }

    /// Whitespace collapses to column gaps; consecutive Latin-ish graphemes
    /// (letters, digits, common punctuation) group into a rotated run.
    private var elements: [VElement] {
        var result: [VElement] = []
        var run = ""

        func flushRun() {
            if !run.isEmpty {
                result.append(.rotatedRun(run))
                run = ""
            }
        }

        for cluster in text {
            if cluster.isWhitespace {
                flushRun()
                continue
            }
            if isLatinRunMember(cluster) {
                run.append(cluster)
            } else {
                flushRun()
                result.append(.upright(String(cluster)))
            }
        }
        flushRun()
        return result
    }

    private func isLatinRunMember(_ cluster: Character) -> Bool {
        cluster.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 0x21 && scalar.value <= 0x7E)  // ASCII letters, digits, punctuation
                || scalar.value == 0xA0
        }
    }
}

/// A Latin run rendered rotated 90° clockwise inside the vertical flow.
/// The layout frame is the transpose of the measured text size, measured
/// synchronously via NSAttributedString (cheap, exact).
private struct RotatedRun: View {
    let text: String
    let fontSize: Double
    let weight: Font.Weight
    let color: Color

    var body: some View {
        let measured = (text as NSString).size(
            withAttributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: nsWeight)]
        )
        Text(text)
            .font(.system(size: fontSize, weight: weight, design: .rounded))
            .foregroundStyle(color)
            .fixedSize()
            .rotationEffect(.degrees(90))
            .frame(width: ceil(measured.height), height: ceil(measured.width) + 1)
    }

    private var nsWeight: NSFont.Weight {
        switch weight {
        case .bold: .bold
        case .semibold: .semibold
        case .medium: .medium
        case .light: .light
        case .thin: .thin
        default: .regular
        }
    }
}

// MARK: - Layout

/// Flows subviews top-to-bottom within a column; when the column height is
/// exhausted, continues in a new column to the left (traditional CJK order).
/// Underfilled columns gently spread their elements (vertical justification)
/// so short content doesn't hug the top leaving the rest empty.
struct VerticalTextLayout: Layout {
    var spacing: CGFloat
    var columnSpacing: CGFloat
    var justifyHeight: Bool = false
    var maxJustifySpacing: CGFloat = 12

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
            // Vertical justification: spread a short column to fill the
            // available height, capped so short titles don't fly apart.
            var gapSpacing = spacing
            if justifyHeight, column.indices.count > 1 {
                let natural = column.usedHeight
                let slack = max(0, bounds.height - natural)
                let extra = min(maxJustifySpacing, slack / CGFloat(column.indices.count - 1))
                gapSpacing = spacing + extra
            }
            for index in column.indices {
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: .unspecified
                )
                y += sizes[index].height + gapSpacing
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
