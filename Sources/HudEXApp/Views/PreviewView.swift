import HudEXCore
import SwiftUI

/// The hover card: project name, 当前 / 下一步 / 最新对话.
///
/// Purely informational — no buttons. The style decides the surface: ruled
/// paper with a connector line (skeuomorphic), frosted material, liquid glass,
/// or a bare outline. Geometry always comes from `PreviewAnchor`.
struct PreviewView: View {
    let model: PreviewModel
    let style: AppearanceStyle
    /// Card frame inside the panel, top-left origin.
    let cardRect: CGRect
    /// Connector geometry inside the panel, top-left origin.
    let connector: PreviewConnector?

    static let width: CGFloat = 300

    struct PreviewConnector: Equatable {
        var start: CGPoint
        var control1: CGPoint
        var control2: CGPoint
        var end: CGPoint
    }

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let connector {
                ConnectorShape(connector: connector)
                    .stroke(
                        Color(nsColor: EdgeTagStyle.color(PaletteColor(hex: "#9AA0A8")!)),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                    )
                    .opacity(0.85)
            }
            card
                .frame(width: cardRect.width, height: cardRect.height, alignment: .topLeading)
                .position(x: cardRect.midX, y: cardRect.midY)
        }
    }

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
            ZStack {
                Color(nsColor: EdgeTagStyle.color(isDark
                    ? PaletteColor(hex: "#26262A")!
                    : PaletteColor(hex: "#FBF7EC")!))
                RuledPaperLines(isDark: isDark)
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
            return Color(nsColor: EdgeTagStyle.color(PaletteColor(hex: isDark ? "#3C3C42" : "#E2D9C4")!))
        case .frosted:
            return Color.white.opacity(isDark ? 0.12 : 0.35)
        case .glass:
            return Color.white.opacity(isDark ? 0.16 : 0.45)
        case .minimal:
            return Color.secondary.opacity(0.6)
        }
    }

    private var shadowColor: Color {
        switch style {
        case .skeuomorphic: return Color.black.opacity(isDark ? 0.45 : 0.18)
        case .frosted: return Color.black.opacity(0.18)
        case .glass: return Color.black.opacity(0.12)
        case .minimal: return .clear
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ForEach(model.sections) { section in
                SectionBlockView(
                    title: section.title,
                    text: section.body,
                    lineLimit: section.singleLine ? 1 : 4
                )
                .padding(.top, 2)
            }
            if let hint = model.emptyHint {
                Text(hint)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: PreviewView.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
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
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                Text(model.statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let updated = model.updatedLine {
                    Text("·").font(.system(size: 11)).foregroundStyle(.tertiary)
                    Text(updated).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Faint ruled lines, the cheapest possible "paper" cue.
private struct RuledPaperLines: View {
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
            .stroke(
                Color(nsColor: EdgeTagStyle.color(PaletteColor(hex: isDark ? "#33333A" : "#E7DFCC")!)),
                lineWidth: 0.8
            )
        }
    }
}

/// The curved "string" from the tag's hole to the card.
private struct ConnectorShape: Shape {
    let connector: PreviewView.PreviewConnector

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: connector.start)
        path.addCurve(
            to: connector.end,
            control1: connector.control1,
            control2: connector.control2
        )
        return path
    }

    var animatableData: EmptyAnimatableData { EmptyAnimatableData() }
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
