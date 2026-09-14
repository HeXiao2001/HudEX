import AppKit
import HudEXCore
import SwiftUI

/// Base panel for every HudEX surface.
///
/// `NSPanel` (not `NSWindow`) with `.nonactivatingPanel` + `.borderless` never
/// takes focus away from the app being used. Where it may appear is decided by
/// `PanelVisibility`: by default the bookmarks stay on the desktop they were
/// created on and never cover a full-screen app.
class HudEXPanel: NSPanel {
    /// Edge tabs must never become key: clicking them cannot interrupt typing.
    var allowsKeyStatus = false

    override var canBecomeKey: Bool { allowsKeyStatus }
    override var canBecomeMain: Bool { false }
}

enum HudEXPanelFactory {
    /// Lowest window level that stays above ordinary windows and full-screen
    /// apps. `statusBar` is only used when `floating` proved insufficient.
    static let tagLevel: NSWindow.Level = .floating

    /// AppKit flags for a visibility mode: the two that decide whether the
    /// bookmarks follow the user across desktops and sit above full-screen apps.
    static func collectionBehavior(for visibility: PanelVisibility) -> NSWindow.CollectionBehavior {
        let flags = visibility.collectionBehaviorFlags
        var behavior: NSWindow.CollectionBehavior = [.stationary, .ignoresCycle]
        if flags.joinAllSpaces { behavior.insert(.canJoinAllSpaces) }
        if flags.canJoinAllApplications { behavior.insert(.canJoinAllApplications) }
        if flags.fullScreenAuxiliary { behavior.insert(.fullScreenAuxiliary) }
        return behavior
    }

    static func makePanel(
        level: NSWindow.Level,
        allowsKeyStatus: Bool,
        autoSaves: Bool = false,
        visibility: PanelVisibility = .mainDesktopOnly
    ) -> HudEXPanel {
        let panel = HudEXPanel(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.allowsKeyStatus = allowsKeyStatus
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = level
        panel.collectionBehavior = Self.collectionBehavior(for: visibility)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
        return panel
    }

    /// A real window for the full project view: it is a deliberate, user
    /// initiated surface, so it looks and behaves like a normal macOS window.
    static func makeDetailWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        window.animationBehavior = .default
        window.setFrameAutosaveName("HudEXDetailWindow")
        window.minSize = NSSize(width: 380, height: 320)
        return window
    }
}

/// Hosts SwiftUI content and reports the mouse position while the panel is not
/// even the key window.
///
/// `NSTrackingArea` with `.activeAlways` is what makes hover work while another
/// app is frontmost — no Accessibility permission, no global event monitor, no
/// polling.
final class HoverTrackingView<Content: View>: NSView {
    /// Reports the mouse position in screen coordinates, `nil` on exit.
    var onHover: ((CGPoint?) -> Void)?

    private let hostingView: FirstMouseHostingView<Content>
    /// The view currently rendered, so callers can release it (see
    /// `PreviewPanelController.releaseRenderedCard`).
    private(set) var rootView: Content
    private var trackingArea: NSTrackingArea?

    init(rootView: Content) {
        self.rootView = rootView
        hostingView = FirstMouseHostingView(rootView: rootView)
        super.init(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used by HudEX")
    }

    func update(rootView: Content) {
        self.rootView = rootView
        hostingView.rootView = rootView
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        report(event)
    }

    override func mouseEntered(with event: NSEvent) {
        report(event)
    }

    override func mouseDragged(with event: NSEvent) {
        report(event)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(nil)
    }

    /// HudEX panels never activate the app, so the window is usually not key.
    /// Without this the first click would only be used to bring the window
    /// forward and the preview buttons would appear dead.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func report(_ event: NSEvent) {
        guard let window else { return }
        onHover?(window.convertPoint(toScreen: event.locationInWindow))
    }
}


/// `NSHostingView` that delivers the first click even while its window is not
/// key, so SwiftUI buttons inside a non-activating panel work on the first try.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
