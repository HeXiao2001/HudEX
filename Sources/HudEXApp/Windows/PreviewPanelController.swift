import AppKit
import HudEXCore
import SwiftUI

/// The hover preview. One reusable panel for every project: hovering ten
/// projects in a session still uses a single window object.
///
/// The panel is informational only, so it never takes key status and never
/// intercepts clicks. While the pointer stays on the same tag, `show` is a
/// no-op: no SwiftUI re-render and no window geometry change.
@MainActor
final class PreviewPanelController {
    /// The pointer entered the panel: cancel any pending hide.
    var onPointerEnter: (() -> Void)?
    /// The pointer left the panel: schedule a hide.
    var onPointerExit: (() -> Void)?
    /// Fired once a minute while the preview is on screen, so the relative age
    /// stays honest without a global timer.
    var onRefreshTick: (() -> Void)?

    private var panel: HudEXPanel?
    private var host: HoverTrackingView<PreviewView>?
    private var refreshTimer: Timer?
    private var model: PreviewModel?
    private var placedTagFrame: CGRect = .zero
    private var placedEdge: DockEdge = .bottom
    private var placedStyle: AppearanceStyle = .default

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Shows (or moves) the preview next to a tag. Cheap when nothing changed.
    func show(
        model: PreviewModel,
        tagFrame: CGRect,
        tagVisualBounds: CGRect? = nil,
        edge: DockEdge,
        style: AppearanceStyle,
        screenVisibleFrame: CGRect
    ) {
        let unchanged = isVisible
            && self.model == model
            && placedTagFrame == tagFrame
            && placedEdge == edge
            && placedStyle == style
        if unchanged { return }

        self.model = model
        self.placedTagFrame = tagFrame
        lastTagFrame = tagFrame
        self.placedEdge = edge
        self.placedStyle = style

        let panel = ensurePanel()
        let host = ensureHost()

        // Pass 1: render the card alone so the panel can ask how tall it wants
        // to be. (Measuring the *placed* layout would size the panel from the
        // previous model, which is what cut the card off before.) The card is
        // as tall as the file makes it, so sections are dropped only when the
        // screen itself is too short.
        var limit: Int? = model.sections.count
        var cardSize = CGSize.zero
        for _ in 0...model.sections.count {
            host.update(rootView: PreviewView(
                model: model,
                style: style,
                layout: .measuring,
                sectionLimit: limit
            ))
            cardSize = measuredCardSize(for: host, screenVisibleFrame: screenVisibleFrame)
            let fits = cardSize.height <= screenVisibleFrame.height - 24
            if fits { break }
            guard let current = limit, current > 1 else { break }
            limit = current - 1
        }
        self.sectionLimit = limit

        // Pass 2: one solver decides where the card goes and how the connector
        // runs; the panel is sized to hold both.
        let anchor = PreviewAnchor.solve(
            tagFrame: tagFrame,
            tagVisualBounds: tagVisualBounds,
            edge: edge,
            cardSize: cardSize,
            visible: screenVisibleFrame,
            usesConnector: style.usesHoleAndConnector
        )
        lastAnchor = anchor
        host.update(rootView: makeRootView(anchor: anchor))
        // The anchor's panel frame already contains the card *and* the curve.
        let frame = anchor.panelFrame.union(anchor.cardFrame)
        lastCardSize = cardSize

        if panel.frame != frame {
            panel.setFrame(frame, display: panel.isVisible)
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
            startRefreshTimer()
        }
    }

    /// Re-renders the current preview (used by the once-a-minute tick).
    func refresh(model: PreviewModel) {
        guard isVisible, self.model != model else { return }
        self.model = model
        if let anchor = lastAnchor {
            ensureHost().update(rootView: makeRootView(anchor: anchor))
        }
    }

    /// Re-solves and re-renders with a new style while the card is on screen,
    /// so switching style in Settings is visible immediately.
    func restyle(_ style: AppearanceStyle, screenVisibleFrame: CGRect) {
        guard isVisible, placedStyle != style, let model, let tagFrame = lastTagFrame else { return }
        placedStyle = style
        show(
            model: model,
            tagFrame: tagFrame,
            edge: placedEdge,
            style: style,
            screenVisibleFrame: screenVisibleFrame
        )
    }

    /// The tag the visible card belongs to.
    private var lastTagFrame: CGRect?
    /// How many sections the visible card is drawing.
    private var sectionLimit: Int?
    private var lastCardSize: CGSize = .zero

    /// The anchor used for the visible preview, so refreshes keep the layout.
    private var lastAnchor: PreviewAnchor?

    private func makeRootView(anchor: PreviewAnchor) -> PreviewView {
        let panel = anchor.panelFrame
        return PreviewView(
            model: model ?? Self.placeholderModel,
            style: placedStyle,
            layout: .placed(
                cardRect: Self.localRect(anchor.cardFrame, in: panel),
                connector: placedStyle.usesHoleAndConnector
                    ? PreviewView.PreviewConnector(
                        start: Self.localPoint(anchor.connectorStart, in: panel),
                        control1: Self.localPoint(anchor.connectorControl1, in: panel),
                        control2: Self.localPoint(anchor.connectorControl2, in: panel),
                        end: Self.localPoint(anchor.connectorEnd, in: panel)
                    )
                    : nil
            ),
            sectionLimit: sectionLimit
        )
    }

    /// Screen rect → panel-local rect in SwiftUI's top-left coordinates.
    static func localRect(_ rect: CGRect, in panel: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - panel.minX,
            y: panel.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func localPoint(_ point: CGPoint, in panel: CGRect) -> CGPoint {
        CGPoint(x: point.x - panel.minX, y: panel.maxY - point.y)
    }

    func hide() {
        panel?.orderOut(nil)
        model = nil
        placedTagFrame = .zero
        lastTagFrame = nil
        stopRefreshTimer()
    }

    // MARK: - Internals

    private func ensurePanel() -> HudEXPanel {
        if let panel { return panel }
        // The preview never becomes key and never asks for key status, so
        // hovering can never disturb the frontmost application.
        let panel = HudEXPanelFactory.makePanel(level: .floating, allowsKeyStatus: false)
        panel.contentView = ensureHost()
        self.panel = panel
        return panel
    }

    private func ensureHost() -> HoverTrackingView<PreviewView> {
        if let host { return host }
        let host = HoverTrackingView(
            rootView: PreviewView(
                model: model ?? Self.placeholderModel,
                style: placedStyle,
                layout: .measuring
            )
        )
        host.onHover = { [weak self] point in
            guard let self else { return }
            if point == nil {
                self.onPointerExit?()
            } else {
                self.onPointerEnter?()
            }
        }
        self.host = host
        return host
    }

    /// The card's own size: the panel around it is computed later.
    private func measuredCardSize(
        for host: HoverTrackingView<PreviewView>,
        screenVisibleFrame: CGRect
    ) -> CGSize {
        let fitting = host.fittingSize
        let width = min(max(fitting.width, PreviewView.minimumWidth), PreviewView.maximumWidth)
        let maximumHeight = max(160, screenVisibleFrame.height - 24)
        let height = min(max(fitting.height, 90), maximumHeight)
        return CGSize(width: width.rounded(), height: height.rounded())
    }

    // MARK: - Timer

    private func startRefreshTimer() {
        stopRefreshTimer()
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.onRefreshTick?()
            }
        }
        timer.tolerance = 20
        refreshTimer = timer
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private static let placeholderModel = PreviewModel(
        projectID: "",
        role: .active,
        colorOverride: nil,
        title: "",
        shortTitle: "",
        statusText: "",
        updatedLine: nil,
        relativeAge: nil,
        sections: [],
        emptyHint: nil
    )
}

/// The full project window. A single window object is reused for every project.
@MainActor
final class DetailWindowController {
    private var window: NSWindow?
    private var hostingView: NSHostingView<DetailView>?
    private var editAction: (() -> Void)?

    var isVisible: Bool { window?.isVisible ?? false }

    func setEditAction(_ action: @escaping () -> Void) {
        editAction = action
    }

    func show(model: DetailModel, title: String) {
        let window = ensureWindow()
        hostingView?.rootView = DetailView(
            model: model,
            onEdit: { [weak self] in self?.editAction?() }
        )
        window.title = title
        if !window.isVisible {
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    private func ensureWindow() -> NSWindow {
        if let window { return window }
        let window = HudEXPanelFactory.makeDetailWindow()
        let hostingView = NSHostingView(
            rootView: DetailView(
                model: DetailModel(
                    projectID: "",
                    title: "",
                    statusText: "",
                    updatedLine: nil,
                    relativeAge: nil,
                    preamble: nil,
                    sections: []
                ),
                onEdit: { [weak self] in self?.editAction?() }
            )
        )
        window.contentView = hostingView
        self.window = window
        self.hostingView = hostingView
        return window
    }
}
