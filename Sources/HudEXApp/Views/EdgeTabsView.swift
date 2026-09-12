import AppKit
import HudEXCore
import SwiftUI

/// Value types handed to SwiftUI. Panels are re-rendered by replacing these
/// values, which keeps the view tree small and free of observation cycles.
struct EdgeTagModel: Identifiable, Equatable {
    let id: String
    let index: Int
    let shortTitle: String
    let title: String
    let role: TagColorRole
    let size: CGSize
    /// Frame on screen (AppKit coordinates) — used for hover hit testing.
    let screenFrame: CGRect
    /// Frame inside the panel, in SwiftUI coordinates (top-left origin).
    let localFrame: CGRect
}

struct EdgePanelModel: Equatable {
    let edge: DockEdge
    let fontSize: CGFloat
    /// Frame of the whole panel on screen (AppKit coordinates).
    let screenFrame: CGRect
    /// Panel size, matching `screenFrame`.
    let size: CGSize
    let tags: [EdgeTagModel]

    static func empty(edge: DockEdge) -> EdgePanelModel {
        EdgePanelModel(edge: edge, fontSize: 11, screenFrame: .zero, size: .zero, tags: [])
    }
}

/// The tabs of one edge slot.
struct EdgeTabsView: View {
    let model: EdgePanelModel
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(model.tags) { tag in
                EdgeTabView(tag: tag, fontSize: model.fontSize)
                    .frame(width: tag.size.width, height: tag.size.height)
                    .position(x: tag.localFrame.midX, y: tag.localFrame.midY)
            }
        }
        .frame(width: max(1, model.size.width), height: max(1, model.size.height))
    }
}

/// A single solid-colour bookmark. Hover never changes its size: the preview
/// window is what reacts.
struct EdgeTabView: View {
    let tag: EdgeTagModel
    let fontSize: CGFloat

    var body: some View {
        let background = EdgeTagStyle.backgroundColor(for: tag.role)
        let foreground = EdgeTagStyle.textColor(on: background)
        Text(tag.shortTitle)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(Color(nsColor: foreground))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(nsColor: background))
            )
            .accessibilityLabel(Text(tag.title))
            .contextMenu {
                HudEXContextMenu(projectID: tag.id)
            }
    }
}

/// Native context menu on a tag. This is also the recovery path when the Menu
/// Bar icon has been switched off.
struct HudEXContextMenu: View {
    let projectID: String?
    @ObservedObject private var controller = HudEXController.shared
    @ObservedObject private var preferences = Preferences.shared

    var body: some View {
        if let projectID {
            Button("打开项目完整内容") { controller.openDetail(projectID: projectID) }
        }
        Button("打开 Markdown 文件（编辑）") { controller.openMarkdownFile() }
        Button("重新载入") { controller.reloadDocument() }

        Divider()

        Toggle("显示 HudEX 标签", isOn: Binding(
            get: { preferences.showTags },
            set: { preferences.showTags = $0 }
        ))
        Toggle("显示 Menu Bar 图标", isOn: Binding(
            get: { preferences.showMenuBarIcon },
            set: { preferences.showMenuBarIcon = $0 }
        ))

        Button("设置…") { controller.openSettings() }
            .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("退出 HudEX") { controller.quit() }
            .keyboardShortcut("q", modifiers: .command)
    }
}
