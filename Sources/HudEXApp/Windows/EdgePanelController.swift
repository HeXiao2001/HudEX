import AppKit
import HudEXCore
import SwiftUI

/// Owns the tab panels.
///
/// One panel per edge slot (not per project): ten projects still cost at most
/// two windows, and the tabs inside a slot are drawn by a single SwiftUI tree.
@MainActor
final class EdgePanelController {
    /// Reports the hovered project id, `nil` when the pointer leaves the tabs.
    var onHoverChange: ((String?) -> Void)?

    private var panels: [EdgeSlot: HudEXPanel] = [:]
    private var hosts: [EdgeSlot: HoverTrackingView<EdgeTabsView>] = [:]
    private var tagFrames: [EdgeSlot: [(id: String, frame: CGRect)]] = [:]
    private var models: [EdgeSlot: EdgePanelModel] = [:]
    private var hoveredProjectID: String?

    func update(_ models: [EdgeSlot: EdgePanelModel]) {
        self.models = models
        for slot in EdgeSlot.allCases {
            guard let model = models[slot], !model.tags.isEmpty, model.size.width > 0, model.size.height > 0 else {
                hide(slot)
                continue
            }

            let panel = panel(for: slot)
            let host = host(for: slot)
            host.update(rootView: EdgeTabsView(model: model))

            if panel.frame != model.screenFrame {
                panel.setFrame(model.screenFrame, display: panel.isVisible)
            }
            tagFrames[slot] = model.tags.map { ($0.id, $0.screenFrame) }

            if !panel.isVisible {
                panel.orderFrontRegardless()
                Log.debug(Log.window, "edge panel \(slot.rawValue) shown at \(model.screenFrame)")
            }
            SnapshotDebugger.captureSoon("tags-\(slot.rawValue)")
        }
    }

    func hideAll() {
        for slot in EdgeSlot.allCases {
            hide(slot)
        }
        setHovered(nil)
    }

    func hide(_ slot: EdgeSlot) {
        panels[slot]?.orderOut(nil)
        tagFrames[slot] = []
    }

    /// Number of live panels — used by the performance test.
    var panelCount: Int { panels.count }

    /// Applies a new visibility mode to the panels that are already on screen.
    func applyVisibility(_ visibility: PanelVisibility) {
        for panel in panels.values {
            panel.collectionBehavior = HudEXPanelFactory.collectionBehavior(for: visibility)
            // Re-showing is what makes AppKit move the window to the right space.
            if panel.isVisible {
                panel.orderFrontRegardless()
            }
        }
    }

    /// The model of one tag, used to place the hover card precisely.
    func tagModel(forProject id: String) -> EdgeTagModel? {
        for model in models.values {
            if let match = model.tags.first(where: { $0.id == id }) { return match }
        }
        return nil
    }

    /// Current frames, for diagnostics.
    func panelFrames() -> [EdgeSlot: CGRect] {
        panels.compactMapValues { $0.isVisible ? $0.frame : nil }
    }

    // MARK: - Panels

    private func panel(for slot: EdgeSlot) -> HudEXPanel {
        if let panel = panels[slot] { return panel }
        let panel = HudEXPanelFactory.makePanel(
            level: HudEXPanelFactory.tagLevel,
            allowsKeyStatus: false,
            visibility: Preferences.shared.panelVisibility
        )
        panel.contentView = host(for: slot)
        panels[slot] = panel
        Log.trace("panel \(slot.rawValue) collectionBehavior=\(panel.collectionBehavior.rawValue)")
        return panel
    }

    private func host(for slot: EdgeSlot) -> HoverTrackingView<EdgeTabsView> {
        if let host = hosts[slot] { return host }
        let host = HoverTrackingView(rootView: EdgeTabsView(model: .empty(edge: .bottom)))
        host.onHover = { [weak self] point in
            self?.handleHover(point)
        }
        hosts[slot] = host
        return host
    }

    // MARK: - Hover

    /// Runs on every mouse move over a panel, so the common case (the pointer
    /// is still on the same tag) must be free: compare first, work later.
    private func handleHover(_ pointOnScreen: CGPoint?) {
        guard let pointOnScreen else {
            setHovered(nil)
            return
        }
        for slot in EdgeSlot.allCases {
            // Stacked tags overlap: the last one drawn is on top, so it wins the
            // hover, exactly like the pixels suggest.
            for entry in (tagFrames[slot] ?? []).reversed() where entry.frame.contains(pointOnScreen) {
                guard entry.id != hoveredProjectID else { return }
                // A click on a window that is neither key nor activating the app
                // is swallowed by the first-mouse rule before it reaches SwiftUI.
                // Taking key status once per hover (never per mouse move, and
                // never activating HudEX) is what makes the tag context menu
                // work. Doing this on every move event floods the window server
                // and stalls the app.
                panels[slot]?.makeKey()
                setHovered(entry.id)
                return
            }
        }
        setHovered(nil)
    }

    private func setHovered(_ id: String?) {
        guard hoveredProjectID != id else { return }
        hoveredProjectID = id
        onHoverChange?(id)
    }
}
