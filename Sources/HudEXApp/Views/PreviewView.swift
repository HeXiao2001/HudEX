import HudEXCore
import SwiftUI

/// The hover card: project name, 当前 / 下一步 / 最新对话.
///
/// Purely informational — no buttons. Two layouts share the same content:
/// `.measuring` lets the panel ask how tall the card wants to be (before it
/// knows where the card goes), and `.placed` draws the card at the position the
/// anchor solver computed, with the connector line when the style uses one.
struct PreviewView: View {
    enum Layout: Equatable {
        /// Card only, natural size — used once to measure the content.
        case measuring
        /// Card at `cardRect`, plus the connector, both in panel coordinates.
        case placed(cardRect: CGRect, connector: PreviewConnector?)
    }

    struct PreviewConnector: Equatable {
        var start: CGPoint
        var control1: CGPoint
        var control2: CGPoint
        var end: CGPoint
    }

    let model: PreviewModel
    let style: AppearanceStyle
    let layout: Layout
    /// How many sections to draw; the controller lowers this when the card
    /// would not fit on screen. `nil` draws everything the file has.
    var sectionLimit: Int? = nil

    /// Card width. The card is measured to its content, so a project with one
    /// short section gets a narrow note and a long one gets a wider note.
    static let minimumWidth: CGFloat = 240
    static let maximumWidth: CGFloat = 420

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        switch layout {
        case .measuring:
            card
                .fixedSize(horizontal: false, vertical: true)
        case .placed(let cardRect, let connector):
            ZStack(alignment: .topLeading) {
                if let connector {
                    ConnectorShape(connector: connector)
                        .stroke(
                            Color(nsColor: EdgeTagStyle.color(connectorColor)),
                            style: StrokeStyle(lineWidth: 1.3, lineCap: .round)
                        )
                        .opacity(0.9)
                }
                card
                    .frame(width: cardRect.width, height: cardRect.height, alignment: .topLeading)
                    .position(x: cardRect.midX, y: cardRect.midY)
            }
            // No explicit size: the hosting view proposes the panel's bounds, so
            // the card can never be squeezed into a smaller frame.
        }
    }

    private var connectorColor: PaletteColor {
        PaperPalette.rule(for: model.role, isDark: isDark, custom: customColor)
    }

    private var customColor: PaletteColor? {
        model.colorOverride.flatMap { TagPalette.color(named: $0, isDark: isDark) }
    }

    private var appearance: TagAppearance {
        TagAppearanceResolver.appearance(
            role: model.role,
            colorOverride: model.colorOverride,
            isDark: isDark
        )
    }

    // MARK: - Card

    private var card: some View {
        content
            .padding(style == .glass ? 11 : 13)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: style == .minimal ? 0 : 6, y: 2)
    }

    private var cornerRadius: CGFloat {
        switch style {
        case .glass: return 14
        case .skeuomorphic: return 6
        case .frosted: return 10
        case .minimal: return 4
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        switch style {
        case .skeuomorphic:
            // Paper in the tag's own colour: a brown tag opens a brown note.
            ZStack {
                Color(nsColor: EdgeTagStyle.color(appearance.paper(isDark: isDark)))
                RuledPaperLines(color: appearance.rule(isDark: isDark), isDark: isDark)
                PaperGrain(color: appearance.rule(isDark: isDark).withAlpha(isDark ? 0.10 : 0.07))
            }
        case .frosted:
            Rectangle().fill(.regularMaterial)
        case .glass:
            Rectangle().fill(.ultraThinMaterial)
        case .minimal:
            Color.clear
        }
    }

    private var borderColor: Color {
        switch style {
        case .skeuomorphic:
            return Color(nsColor: EdgeTagStyle.color(appearance.rule(isDark: isDark).withAlpha(0.9)))
        case .frosted:
            return Color.white.opacity(isDark ? 0.12 : 0.35)
        case .glass:
            return Color.white.opacity(isDark ? 0.16 : 0.45)
        case .minimal:
            return Color(nsColor: EdgeTagStyle.color(appearance.background)).opacity(0.75)
        }
    }

    private var shadowColor: Color {
        switch style {
        case .skeuomorphic: return Color.black.opacity(isDark ? 0.45 : 0.20)
        case .frosted: return Color.black.opacity(0.18)
        case .glass: return Color.black.opacity(0.12)
        case .minimal: return .clear
        }
    }

    /// The sections actually drawn: whatever the Markdown file contains, in
    /// file order — the card does not assume any particular set.
    var visibleSections: [PreviewSectionModel] {
        guard let sectionLimit else { return model.sections }
        return Array(model.sections.prefix(max(0, sectionLimit)))
    }

    private var headingColor: Color {
        style == .skeuomorphic
            ? Color(nsColor: EdgeTagStyle.color(appearance.softInk(isDark: isDark)))
            : .secondary
    }

    private var bodyColor: Color {
        style == .skeuomorphic
            ? Color(nsColor: EdgeTagStyle.color(appearance.ink(isDark: isDark)))
            : .primary
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ForEach(visibleSections) { section in
                SectionBlockView(
                    title: section.title,
                    text: section.body,
                    lineLimit: section.singleLine ? 2 : 5,
                    titleColor: headingColor
                )
                .padding(.top, 2)
            }
            if visibleSections.count < model.sections.count {
                Text(L10n.t("preview.truncated"))
                    .font(.system(size: 11))
                    .foregroundStyle(headingColor)
            }
            if let hint = model.emptyHint {
                Text(hint)
                    .font(.system(size: 11.5))
                    .foregroundStyle(headingColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(bodyColor)
        .frame(minWidth: PreviewView.minimumWidth, maxWidth: PreviewView.maximumWidth, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if let age = model.relativeAge {
                    Text(age)
                        .font(.system(size: 11))
                        .foregroundStyle(headingColor)
                }
            }
            HStack(spacing: 6) {
                Text(model.statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(headingColor)
                if let updated = model.updatedLine {
                    Text("·").font(.system(size: 11)).foregroundStyle(headingColor.opacity(0.6))
                    Text(updated).font(.system(size: 11)).foregroundStyle(headingColor)
                }
            }
        }
    }
}

/// Faint ruled lines, the cheapest possible "paper" cue.
private struct RuledPaperLines: View {
    let color: PaletteColor
    let isDark: Bool

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 22
            let count = max(1, Int(geometry.size.height / spacing))
            Path { path in
                for index in 1...count {
                    let y = CGFloat(index) * spacing
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
            }
            .stroke(Color(nsColor: EdgeTagStyle.color(color.withAlpha(isDark ? 0.55 : 0.65))), lineWidth: 0.8)
        }
    }
}

/// The tiniest hint of grain: a few diagonal hairlines, no blur, no image.
private struct PaperGrain: View {
    let color: PaletteColor

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let step: CGFloat = 9
                var x: CGFloat = -geometry.size.height
                while x < geometry.size.width {
                    path.move(to: CGPoint(x: x, y: geometry.size.height))
                    path.addLine(to: CGPoint(x: x + geometry.size.height, y: 0))
                    x += step
                }
            }
            .stroke(Color(nsColor: EdgeTagStyle.color(color)), lineWidth: 0.5)
        }
    }
}

/// The curved "string" from the tag's hole to the card.
private struct ConnectorShape: Shape {
    let connector: PreviewView.PreviewConnector

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: connector.start)
        path.addCurve(to: connector.end, control1: connector.control1, control2: connector.control2)
        return path
    }
}

/// The full project text. Reached by right-clicking a tag → “打开项目完整内容”.
struct DetailView: View {
    let model: DetailModel
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let preamble = model.preamble, !preamble.isEmpty {
                        MarkdownBodyView(markdown: preamble)
                    }
                    ForEach(model.sections) { section in
                        SectionBlockView(title: section.title, text: section.body)
                    }
                    if model.sections.isEmpty {
                        Text(L10n.t("detail.emptySections"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Spacer()
                Button(L10n.t("common.edit"), action: onEdit)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 380, minHeight: 320)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.title)
                .font(.system(size: 18, weight: .semibold))
                .textSelection(.enabled)

            HStack(spacing: 6) {
                Text(L10n.t("detail.statusPrefix", model.statusText))
                if let updated = model.updatedLine {
                    Text("·")
                    Text(updated)
                }
                if let age = model.relativeAge {
                    Text("·")
                    Text(age)
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)

            Divider().padding(.top, 2)
        }
    }
}
