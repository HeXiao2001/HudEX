import AppKit
import ApplicationServices
import DeskHUDCore
import SwiftUI

@MainActor
final class HUDWindowManager {
    private struct ManagedWindow {
        let window: NSWindow
        let hostingView: NSHostingView<HUDPanelView>
        let slot: HUDSlot
        let screen: NSScreen
    }

    private var managedWindows: [ManagedWindow] = []
    private var slotStates: [String: PerSlotState] = [:]  // keyed by slot.id
    private var rotationTimer: Timer?
    private var scrollTimer: Timer?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var dockFollowTimer: Timer?
    private var idleRefreshTimer: Timer?
    private var activeConfig: HUDConfig?
    private var activeDocument: HUDDocument?
    private var isMouseNearDock = false
    private var lastMouseLocation: NSPoint = .zero
    private var lastKnownDockRect: NSRect?
    private var debugEnabled = false
    private var lastMouseScreenID: UInt32?
    private var workspaceObservers: [NSObjectProtocol] = []

    private struct PerSlotState {
        var sectionIndex = 0
        var scrollOffset = 0
    }

    func show(document: HUDDocument, config: HUDConfig) {
        closeAll()
        debugEnabled = config.debugLogging
        activeConfig = config
        activeDocument = document

        // Initialize per-slot state for rotation / scroll
        slotStates.removeAll()
        for slot in document.slots {
            slotStates[slot.id] = PerSlotState()
        }

        let screens = HUDDisplayResolver.screens(for: config)
        for screen in screens {
            for slot in document.slots {
                guard slot.anchor == .dockLeft || slot.anchor == .dockRight else { continue }
                let state = slotStates[slot.id] ?? PerSlotState()
                let frame = frameForSlot(slot, on: screen, config: config, mouseLocation: nil)
                let view = makePanelView(slot: slot, config: config, frame: frame, screen: screen, state: state)
                let hostingView = NSHostingView(rootView: view)
                hostingView.frame = NSRect(origin: .zero, size: frame.size)
                hostingView.autoresizingMask = [.width, .height]

                let window = NSWindow(
                    contentRect: frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false,
                    screen: screen
                )
                window.contentView = Self.makeContentView(
                    hosting: hostingView,
                    background: config.backgroundStyle,
                    size: frame.size,
                    cornerRadius: config.window.cornerRadius
                )
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = false
                window.ignoresMouseEvents = true
                window.level = .floating
                window.collectionBehavior = collectionBehavior(for: config)
                window.isReleasedWhenClosed = false
                window.orderFrontRegardless()
                managedWindows.append(ManagedWindow(window: window, hostingView: hostingView, slot: slot, screen: screen))
            }
        }

        installMouseMonitor(config: config)
        installIdleRefreshTimer()
        installWorkspaceObservers()
        installRotationTimer()
        installScrollTimer()
        syncContextFile()
    }

    /// Wraps the SwiftUI hosting view in the configured background.
    /// `.glass` uses the AppKit Liquid Glass API (WWDC25): content goes into
    /// `NSGlassEffectView.contentView` so AppKit applies the correct visual
    /// treatments. Pre-macOS 26 falls back to behind-window vibrancy.
    private static func makeContentView(
        hosting: NSHostingView<HUDPanelView>,
        background: DeskHUDCore.BackgroundStyle,
        size: NSSize,
        cornerRadius: Double
    ) -> NSView {
        guard background == .glass else { return hosting }

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
            glass.cornerRadius = cornerRadius
            glass.contentView = hosting
            return glass
        }

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        let vibrancy = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        vibrancy.material = .hudWindow
        vibrancy.blendingMode = .behindWindow
        vibrancy.state = .active
        vibrancy.wantsLayer = true
        vibrancy.layer?.cornerRadius = cornerRadius
        vibrancy.layer?.masksToBounds = true
        vibrancy.autoresizingMask = [.width, .height]
        container.addSubview(vibrancy)
        container.addSubview(hosting)
        return container
    }

    /// Apply config changes to existing windows without tearing them down.
    /// When display target, fixed display ID, or background style changes,
    /// rebuilds all windows (background lives on the window's content view).
    func reconfigure(config: HUDConfig) {
        let needsRebuild = activeConfig?.displays != config.displays
            || activeConfig?.fixedDisplayID != config.fixedDisplayID
            || activeConfig?.backgroundStyle != config.backgroundStyle

        if needsRebuild, let document = activeDocument {
            show(document: document, config: config)
            return
        }

        activeConfig = config
        debugEnabled = config.debugLogging
        stopScrollTimer()
        installScrollTimer()
        for managedWindow in managedWindows {
            let state = slotStates[managedWindow.slot.id] ?? PerSlotState()
            let frame = frameForSlot(
                managedWindow.slot,
                on: managedWindow.screen,
                config: config,
                mouseLocation: nil
            )
            managedWindow.hostingView.rootView = makePanelView(
                slot: managedWindow.slot,
                config: config,
                frame: frame,
                screen: managedWindow.screen,
                state: state
            )
            managedWindow.hostingView.frame = NSRect(origin: .zero, size: frame.size)
            managedWindow.window.setFrame(frame, display: true, animate: false)
            managedWindow.window.collectionBehavior = collectionBehavior(for: config)
        }
    }

    func closeAll() {
        stopDockFollowTimer()
        stopIdleRefreshTimer()
        stopRotationTimer()
        stopScrollTimer()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }

        for managedWindow in managedWindows {
            managedWindow.window.orderOut(nil)
            managedWindow.window.close()
        }
        managedWindows.removeAll()
    }

    private func collectionBehavior(for config: HUDConfig) -> NSWindow.CollectionBehavior {
        if config.fullscreenMode == .desktopOnly {
            return [.stationary, .ignoresCycle]
        }
        return [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    private func installMouseMonitor(config: HUDConfig) {
        // Global: fires when another app is active
        if globalMouseMonitor == nil {
            globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleMouseMoved()
                }
            }
        }
        // Local: fires when DeskHUD (or its Settings window) is active
        if localMouseMonitor == nil {
            localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.handleMouseMoved()
                }
                return event
            }
        }
    }

    private func handleMouseMoved() {
        guard let config = activeConfig else { return }

        // Mouse Display: rebuild HUD when mouse moves to another screen
        if config.displays == .mouse {
            let mouseScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            let currentID = mouseScreen.flatMap { screenID($0) }
            if currentID != lastMouseScreenID {
                lastMouseScreenID = currentID
                if let document = activeDocument {
                    show(document: document, config: config)
                    return
                }
            }
        }

        lastMouseLocation = NSEvent.mouseLocation
        let shouldFollow = isInDockTrackingArea(lastMouseLocation)
        if shouldFollow == isMouseNearDock { return }

        isMouseNearDock = shouldFollow
        if shouldFollow {
            stopIdleRefreshTimer()
            startDockFollowTimer()
        } else {
            stopDockFollowTimer()
            updateFrames(config: config, mouseLocation: nil)
            installIdleRefreshTimer()
        }
    }

    /// Runs at 60 Hz to match standard display refresh rate.
    /// CADisplayLink is not available for standalone AppKit use on macOS, so a
    /// Timer is the most portable approach.
    private func startDockFollowTimer() {
        guard dockFollowTimer == nil else { return }
        dockFollowTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.timerTick()
            }
        }
    }

    private func timerTick() {
        guard let config = activeConfig else { return }
        lastMouseLocation = NSEvent.mouseLocation
        if isInDockTrackingArea(lastMouseLocation) {
            updateFrames(config: config, mouseLocation: lastMouseLocation)
        } else {
            isMouseNearDock = false
            stopDockFollowTimer()
            updateFrames(config: config, mouseLocation: nil)
        }
    }

    private func stopDockFollowTimer() {
        dockFollowTimer?.invalidate()
        dockFollowTimer = nil
    }

    // MARK: - Idle refresh (catches Dock width changes when mouse is away)

    /// Checks the AX Dock rect every 2 seconds when the mouse is not near the Dock.
    /// If the Dock width changed (user added/removed an app, etc.), the HUD panels
    /// adjust automatically.
    private func installIdleRefreshTimer() {
        guard idleRefreshTimer == nil else { return }
        idleRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.idleRefreshTick()
            }
        }
    }

    private func idleRefreshTick() {
        guard !isMouseNearDock,
              let config = activeConfig else { return }
        // Snapshot current AX Dock rect. If different from last known, HUDs need updating.
        for screen in NSScreen.screens {
            if let currentRect = accessibilityDockRect(in: screen.frame) {
                if lastKnownDockRect != currentRect {
                    lastKnownDockRect = currentRect
                    updateFrames(config: config, mouseLocation: nil)
                    logDebug("idleRefresh dockChanged rect=\(currentRect.debugDescription)")
                }
                return
            }
        }
    }

    private func stopIdleRefreshTimer() {
        idleRefreshTimer?.invalidate()
        idleRefreshTimer = nil
    }

    // MARK: - Rotation timer (cycles between sections per slot)

    private func installRotationTimer() {
        guard activeConfig != nil, let document = activeDocument else { return }
        let anyRotationEnabled = document.slots.contains { $0.rotation.enabled }
        guard anyRotationEnabled else { return }
        stopRotationTimer()

        // Find the minimum rotation interval across all slots
        let minInterval = document.slots
            .filter { $0.rotation.enabled }
            .map { $0.rotation.intervalSeconds }
            .min() ?? 45

        rotationTimer = Timer.scheduledTimer(withTimeInterval: minInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rotationTick()
            }
        }
    }

    private func rotationTick() {
        guard let document = activeDocument, let config = activeConfig else { return }
        var changed = false
        for slot in document.slots where slot.rotation.enabled {
            let sections = slot.resolvedSections
            guard sections.count > 1 else { continue }
            var state = slotStates[slot.id] ?? PerSlotState()
            state.sectionIndex = (state.sectionIndex + 1) % sections.count
            state.scrollOffset = 0
            slotStates[slot.id] = state
            changed = true
        }
        if changed { refreshManagedWindows(config: config) }
    }

    private func stopRotationTimer() {
        rotationTimer?.invalidate()
        rotationTimer = nil
    }

    // MARK: - Scroll timer (auto-scrolls items within each section)

    private func installScrollTimer() {
        guard scrollTimer == nil, let config = activeConfig else { return }
        let interval = config.window.scrollIntervalSeconds
        scrollTimer?.invalidate()
        scrollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scrollTick()
            }
        }
    }

    /// Adjust scroll timer interval to match the current item's `durationSeconds`,
    /// falling back to the global `scrollIntervalSeconds`.
    private func rescheduleScrollTimer() {
        guard let config = activeConfig, let document = activeDocument else { return }
        let defaultInterval = config.window.scrollIntervalSeconds
        var targetInterval = defaultInterval
        for slot in document.slots {
            let sections = slot.resolvedSections
            let state = slotStates[slot.id] ?? PerSlotState()
            guard state.sectionIndex < sections.count else { continue }
            let section = sections[state.sectionIndex]
            guard state.scrollOffset < section.items.count else { continue }
            let item = section.items[state.scrollOffset]
            if let custom = item.durationSeconds, custom > 0 {
                targetInterval = custom
            }
        }
        guard scrollTimer?.timeInterval != targetInterval else { return }
        scrollTimer?.invalidate()
        scrollTimer = Timer.scheduledTimer(withTimeInterval: targetInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scrollTick()
            }
        }
    }

    private func scrollTick() {
        guard let document = activeDocument, let config = activeConfig else { return }
        var changed = false
        for slot in document.slots {
            let sections = slot.resolvedSections
            guard !sections.isEmpty else { continue }
            var state = slotStates[slot.id] ?? PerSlotState()
            guard state.sectionIndex < sections.count else { continue }
            let section = sections[state.sectionIndex]
            let count = section.items.count
            guard count > 0 else { continue }
            // Advance one item at a time for smooth browsing
            state.scrollOffset = (state.scrollOffset + 1) % max(1, count)
            slotStates[slot.id] = state
            changed = true
        }
        if changed { refreshManagedWindows(config: config) }
    }

    private func stopScrollTimer() {
        scrollTimer?.invalidate()
        scrollTimer = nil
    }

    /// Always 2 items visible — matches HUDPanelView.
    private func maxVisibleItemCount() -> Int { 2 }

    /// Push current slot state to every displayed window.
    /// Uses the current mouse location when the mouse is near the Dock so
    /// the frame accounts for Dock magnification.
    private func refreshManagedWindows(config: HUDConfig) {
        let mouse: NSPoint? = isMouseNearDock ? lastMouseLocation : nil
        for managedWindow in managedWindows {
            let state = slotStates[managedWindow.slot.id] ?? PerSlotState()
            let frame = frameForSlot(
                managedWindow.slot,
                on: managedWindow.screen,
                config: config,
                mouseLocation: mouse
            )
            managedWindow.window.setFrame(frame, display: true, animate: false)
            managedWindow.hostingView.rootView = makePanelView(
                slot: managedWindow.slot,
                config: config,
                frame: frame,
                screen: managedWindow.screen,
                state: state
            )
            managedWindow.hostingView.frame = NSRect(origin: .zero, size: frame.size)
        }
        rescheduleScrollTimer()
    }

    // MARK: - Workspace events (triggers immediate Dock width re-check)

    private func installWorkspaceObservers() {
        let launched = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dockMayHaveChanged()
            }
        }
        let terminated = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dockMayHaveChanged()
            }
        }
        workspaceObservers = [launched, terminated]
    }

    private func dockMayHaveChanged() {
        guard activeConfig != nil, !isMouseNearDock else { return }
        // Invalidate cached rect so the next idle tick (or immediate check) picks up the change.
        lastKnownDockRect = nil
        // Immediate single check after a short debounce (the Dock animates its size change).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.activeConfig != nil, !self.isMouseNearDock else { return }
            self.idleRefreshTick()
        }
    }

    private func updateFrames(config: HUDConfig, mouseLocation: NSPoint?) {
        for managedWindow in managedWindows {
            let state = slotStates[managedWindow.slot.id] ?? PerSlotState()
            let frame = frameForSlot(managedWindow.slot, on: managedWindow.screen, config: config, mouseLocation: mouseLocation)
            guard !managedWindow.window.frame.equalTo(frame) else { continue }
            managedWindow.hostingView.rootView = makePanelView(
                slot: managedWindow.slot,
                config: config,
                frame: frame,
                screen: managedWindow.screen,
                state: state
            )
            managedWindow.hostingView.frame = NSRect(origin: .zero, size: frame.size)
            managedWindow.window.setFrame(frame, display: true, animate: false)
        }
    }

    /// Tracks proximity to the Dock regardless of which screen edge it sits on:
    /// bottom band for horizontal Docks, side band for vertical Docks.
    private func isInDockTrackingArea(_ point: NSPoint) -> Bool {
        for screen in NSScreen.screens {
            let screenFrame = screen.frame
            let visible = screen.visibleFrame
            let bottomBand = max(0, visible.minY - screenFrame.minY)
            if bottomBand > 24 {
                let trackingHeight = max(bottomBand + 100, 180)
                let trackingRect = NSRect(
                    x: screenFrame.minX,
                    y: screenFrame.minY,
                    width: screenFrame.width,
                    height: trackingHeight
                )
                if trackingRect.contains(point) { return true }
                continue
            }
            let leftBand = max(0, visible.minX - screenFrame.minX)
            if leftBand > 24 {
                let trackingWidth = max(leftBand + 100, 180)
                let trackingRect = NSRect(
                    x: screenFrame.minX,
                    y: screenFrame.minY,
                    width: trackingWidth,
                    height: screenFrame.height
                )
                if trackingRect.contains(point) { return true }
                continue
            }
            let rightBand = max(0, screenFrame.maxX - visible.maxX)
            if rightBand > 24 {
                let trackingWidth = max(rightBand + 100, 180)
                let trackingRect = NSRect(
                    x: screenFrame.maxX - trackingWidth,
                    y: screenFrame.minY,
                    width: trackingWidth,
                    height: screenFrame.height
                )
                if trackingRect.contains(point) { return true }
            }
        }
        return false
    }

    private struct DockGeometry {
        let isVertical: Bool
        let onLeftEdge: Bool
    }

    /// Which screen edge hosts the Dock (inferred from the band `visibleFrame`
    /// reserves). Auto-hidden Docks are not detectable this way.
    private func dockGeometry(on screen: NSScreen) -> DockGeometry {
        let screenFrame = screen.frame
        let visible = screen.visibleFrame
        if visible.minY - screenFrame.minY > 24 { return DockGeometry(isVertical: false, onLeftEdge: false) }
        if visible.minX - screenFrame.minX > 24 { return DockGeometry(isVertical: true, onLeftEdge: true) }
        if screenFrame.maxX - visible.maxX > 24 { return DockGeometry(isVertical: true, onLeftEdge: false) }
        return DockGeometry(isVertical: false, onLeftEdge: false)
    }

    /// Builds the panel view for a slot. For vertical Docks the logical
    /// (length × thickness) layout is transposed and rendered rotated so text
    /// lines run along the panel's long axis.
    private func makePanelView(
        slot: HUDSlot,
        config: HUDConfig,
        frame: NSRect,
        screen: NSScreen,
        state: PerSlotState
    ) -> HUDPanelView {
        let geo = dockGeometry(on: screen)
        return HUDPanelView(
            slot: slot,
            config: config,
            width: geo.isVertical ? frame.height : frame.width,
            height: geo.isVertical ? frame.width : frame.height,
            sectionIndex: state.sectionIndex,
            scrollOffset: state.scrollOffset,
            rotationDegrees: geo.isVertical ? (geo.onLeftEdge ? 90 : -90) : nil
        )
    }

    private func frameForSlot(
        _ slot: HUDSlot,
        on screen: NSScreen,
        config: HUDConfig,
        mouseLocation: NSPoint?
    ) -> NSRect {
        let screenFrame = screen.frame
        let visible = screen.visibleFrame
        let margin = config.window.margin
        let preferredSize = NSSize(width: config.window.width, height: config.window.height)
        let geo = dockGeometry(on: screen)

        if !geo.isVertical {
            let bottomDockBandHeight = max(0, visible.minY - screenFrame.minY)
            if bottomDockBandHeight > 24 {
                return frameForBottomDockSlot(
                    slot,
                    screenFrame: screenFrame,
                    dockBandHeight: bottomDockBandHeight,
                    preferredSize: preferredSize,
                    margin: margin,
                    mouseLocation: mouseLocation
                )
            }
            // No Dock detected: fall back to plain corner placement.
            return frameForSideDockSlot(slot, visible: visible, preferredSize: preferredSize, margin: margin)
        }

        let dockBandWidth = geo.onLeftEdge
            ? max(0, visible.minX - screenFrame.minX)
            : max(0, screenFrame.maxX - visible.maxX)
        return frameForVerticalDockSlot(
            slot,
            screenFrame: screenFrame,
            visible: visible,
            dockBandWidth: dockBandWidth,
            dockIsOnLeftEdge: geo.onLeftEdge,
            preferredSize: preferredSize,
            margin: margin,
            mouseLocation: mouseLocation
        )
    }

    /// Vertical Dock (left or right screen edge): panels hug the Dock's free
    /// vertical span — `dockLeft` above the Dock, `dockRight` below it
    /// (reading order is preserved). Config axes rotate with the Dock:
    /// `height` stays the band thickness (now the panel's width), and `width`
    /// (0 = auto) becomes the panel's vertical length.
    private func frameForVerticalDockSlot(
        _ slot: HUDSlot,
        screenFrame: NSRect,
        visible: NSRect,
        dockBandWidth: CGFloat,
        dockIsOnLeftEdge: Bool,
        preferredSize: NSSize,
        margin: CGFloat,
        mouseLocation: NSPoint?
    ) -> NSRect {
        let dockExclusion = estimatedVerticalDockExclusionRect(
            in: screenFrame,
            visible: visible,
            dockBandWidth: dockBandWidth,
            dockIsOnLeftEdge: dockIsOnLeftEdge,
            mouseLocation: mouseLocation
        )
        let gap: CGFloat = 6
        let minLength: CGFloat = 150
        let thickness = min(preferredSize.height, max(54, dockBandWidth - 10))
        let maxLen = preferredSize.width > 0 ? preferredSize.width : .greatestFiniteMagnitude
        // Center the panel inside the Dock's horizontal band, like the bottom-Dock case.
        let x: CGFloat
        if dockIsOnLeftEdge {
            x = screenFrame.minX + max(5, (dockBandWidth - thickness) / 2)
        } else {
            x = screenFrame.maxX - max(5, (dockBandWidth - thickness) / 2) - thickness
        }

        switch slot.anchor {
        case .dockLeft:  // above the Dock, top edge hugging the menu-bar margin
            let available = max(0, visible.maxY - margin - (dockExclusion.maxY + gap))
            let length = min(maxLen, max(minLength, available))
            let y = visible.maxY - margin - length
            return NSRect(x: x.rounded(), y: y.rounded(), width: thickness.rounded(), height: length.rounded())
        case .dockRight:  // below the Dock, bottom edge hugging the screen corner
            let available = max(0, (dockExclusion.minY - gap) - (screenFrame.minY + margin))
            let length = min(maxLen, max(minLength, available))
            let y = screenFrame.minY + margin
            return NSRect(x: x.rounded(), y: y.rounded(), width: thickness.rounded(), height: length.rounded())
        }
    }

    private func estimatedVerticalDockExclusionRect(
        in screenFrame: NSRect,
        visible: NSRect,
        dockBandWidth: CGFloat,
        dockIsOnLeftEdge: Bool,
        mouseLocation: NSPoint?
    ) -> NSRect {
        // Preferred: use Accessibility API for exact Dock bounds
        if let accessibilityRect = accessibilityDockRect(in: screenFrame) {
            logDebug("dockSource=AX rect=\(accessibilityRect.debugDescription)")
            // Expand along the Dock's length so panels keep a small end gap.
            return accessibilityRect.insetBy(dx: 0, dy: -4)
        }

        // Fallback: estimate Dock length from preferences, honoring pinning.
        let estimatedLength = estimateDockLengthFromPreferences(axisLength: screenFrame.height)
        var minY: CGFloat, maxY: CGFloat
        switch dockPinning() {
        case "start":  // pinned to the top edge, below the menu bar
            maxY = visible.maxY
            minY = maxY - estimatedLength
        case "end":    // pinned to the bottom edge
            minY = visible.minY
            maxY = minY + estimatedLength
        default:       // centered on the screen edge
            minY = screenFrame.midY - estimatedLength / 2
            maxY = screenFrame.midY + estimatedLength / 2
        }

        if let mouseLocation {
            let magnifiedRadius = max(210, dockBandWidth * 2.4)
            minY = min(minY, mouseLocation.y - magnifiedRadius)
            maxY = max(maxY, mouseLocation.y + magnifiedRadius)
        }
        minY = max(screenFrame.minY, minY)
        maxY = min(screenFrame.maxY, maxY)

        let x = dockIsOnLeftEdge ? screenFrame.minX : screenFrame.maxX - dockBandWidth
        let rect = NSRect(x: x, y: minY, width: dockBandWidth, height: max(0, maxY - minY))
        logDebug("dockSource=prefs rect=\(rect.debugDescription)")
        return rect
    }

    /// Dock pinning preference: "start" / "middle" / "end" (string) on modern
    /// macOS, legacy integers on older systems.
    private func dockPinning() -> String {
        guard let obj = UserDefaults(suiteName: "com.apple.dock")?.object(forKey: "pinning") else {
            return "middle"
        }
        if let s = obj as? String { return s }
        if let n = obj as? Int {
            switch n {
            case -1: return "start"
            case 1: return "end"
            default: return "middle"
            }
        }
        return "middle"
    }

    private func frameForBottomDockSlot(
        _ slot: HUDSlot,
        screenFrame: NSRect,
        dockBandHeight: CGFloat,
        preferredSize: NSSize,
        margin: CGFloat,
        mouseLocation: NSPoint?
    ) -> NSRect {
        let dockExclusion = estimatedDockExclusionRect(
            in: screenFrame,
            dockBandHeight: dockBandHeight,
            mouseLocation: mouseLocation
        )
        let gap: CGFloat = 6
        let minWidth: CGFloat = 150
        let height = min(preferredSize.height, max(54, dockBandHeight - 10))
        let y = screenFrame.minY + max(5, (dockBandHeight - height) / 2)

        switch slot.anchor {
        case .dockLeft:
            let leftAvailable = max(0, dockExclusion.minX - screenFrame.minX - margin - gap)
            let maxWidth = preferredSize.width > 0 ? preferredSize.width : .greatestFiniteMagnitude
            let width = min(maxWidth, max(minWidth, leftAvailable))
            let x = screenFrame.minX + margin
            return NSRect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())
        case .dockRight:
            let rightAvailable = max(0, screenFrame.maxX - dockExclusion.maxX - margin - gap)
            let maxWidth = preferredSize.width > 0 ? preferredSize.width : .greatestFiniteMagnitude
            let width = min(maxWidth, max(minWidth, rightAvailable))
            let x = screenFrame.maxX - margin - width
            return NSRect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())
        }
    }

    private func estimatedDockExclusionRect(
        in screenFrame: NSRect,
        dockBandHeight: CGFloat,
        mouseLocation: NSPoint?
    ) -> NSRect {
        // Preferred: use Accessibility API for exact Dock bounds
        if let accessibilityRect = accessibilityDockRect(in: screenFrame) {
            logDebug("dockSource=AX rect=\(accessibilityRect.debugDescription)")
            // Minimal expansion for Dock visual edge padding
            return accessibilityRect.insetBy(dx: -4, dy: 0)
        }

        // Fallback: estimate Dock width from preferences + conservative heuristic
        let estimatedWidth = estimateDockLengthFromPreferences(axisLength: screenFrame.width)
        var minX = screenFrame.midX - estimatedWidth / 2
        var maxX = screenFrame.midX + estimatedWidth / 2

        if let mouseLocation, screenFrame.contains(mouseLocation) {
            let magnifiedRadius = max(210, dockBandHeight * 2.4)
            minX = min(minX, mouseLocation.x - magnifiedRadius)
            maxX = max(maxX, mouseLocation.x + magnifiedRadius)
        }

        minX = max(screenFrame.minX, minX)
        maxX = min(screenFrame.maxX, maxX)
        let rect = NSRect(x: minX, y: screenFrame.minY, width: max(0, maxX - minX), height: dockBandHeight)
        logDebug("dockSource=prefs rect=\(rect.debugDescription)")
        return rect
    }

    /// Estimate Dock length along its axis from `com.apple.dock` preferences.
    /// Biases conservative (longer estimate) to avoid HUD panels overlapping the Dock.
    /// Pass screen width for bottom Docks, screen height for side Docks.
    private func estimateDockLengthFromPreferences(axisLength: CGFloat) -> CGFloat {
        let dockDefaults = UserDefaults(suiteName: "com.apple.dock")
        let tileSize = CGFloat(dockDefaults?.double(forKey: "tilesize") ?? 64)
        let persistentAppCount = dockDefaults?.array(forKey: "persistent-apps")?.count ?? 0
        let persistentOtherCount = dockDefaults?.array(forKey: "persistent-others")?.count ?? 0

        // Always-visible Dock fixtures (Finder, Trash) + generous running-app buffer
        let estimatedIcons = max(persistentAppCount + persistentOtherCount + 10, 12)
        let spacingPerIcon: CGFloat = 10
        let rawLength = tileSize * CGFloat(estimatedIcons) + spacingPerIcon * CGFloat(estimatedIcons - 1)

        // Clamp: never shorter than 50% or longer than 92% of the screen axis
        let clamped = min(axisLength * 0.92, max(axisLength * 0.50, rawLength))
        return clamped.rounded()
    }

    private func accessibilityDockRect(in screenFrame: NSRect) -> NSRect? {
        guard AXIsProcessTrusted() else { return nil }
        guard let dockApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dock" }) else {
            return nil
        }

        let dockElement = AXUIElementCreateApplication(dockApp.processIdentifier)
        guard let children = accessibilityChildren(of: dockElement) else { return nil }

        for child in children {
            // The Dock's icon list reports either orientation depending on
            // which screen edge it is pinned to, so accept both.
            guard accessibilityString(kAXRoleAttribute, of: child) == kAXListRole else { continue }
            guard let topLeftRect = accessibilityRect(of: child) else { continue }
            let appKitRect = convertTopLeftRectToAppKit(topLeftRect, in: screenFrame)
            guard appKitRect.intersects(screenFrame) else { continue }
            return appKitRect.intersection(screenFrame)
        }

        return nil
    }

    private func accessibilityChildren(of element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? [AXUIElement]
    }

    private func accessibilityString(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private func accessibilityRect(of element: AXUIElement) -> NSRect? {
        guard let position = accessibilityPoint(kAXPositionAttribute, of: element),
              let size = accessibilitySize(kAXSizeAttribute, of: element) else {
            return nil
        }
        return NSRect(origin: position, size: size)
    }

    private func accessibilityPoint(_ attribute: String, of element: AXUIElement) -> NSPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(axValue, .cgPoint, &point)
        return point
    }

    private func accessibilitySize(_ attribute: String, of element: AXUIElement) -> NSSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else { return nil }
        var size = CGSize.zero
        AXValueGetValue(axValue, .cgSize, &size)
        return size
    }

    private func convertTopLeftRectToAppKit(_ rect: NSRect, in screenFrame: NSRect) -> NSRect {
        NSRect(
            x: rect.minX,
            y: screenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private func screenID(_ screen: NSScreen) -> UInt32? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32
    }

    private func logDebug(_ message: String) {
        guard debugEnabled else { return }
        let line = "\(Date()) \(message)\n"
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("DeskHUDDockDebug.log")
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                _ = try? handle.write(contentsOf: data)
                _ = try? handle.close()
            } else {
                _ = try? data.write(to: url)
            }
        }
    }

    private func frameForSideDockSlot(
        _ slot: HUDSlot,
        visible: NSRect,
        preferredSize: NSSize,
        margin: CGFloat
    ) -> NSRect {
        let effectiveWidth = preferredSize.width > 0 ? preferredSize.width : (visible.width - margin * 2)
        let x: CGFloat
        switch slot.anchor {
        case .dockLeft:
            x = visible.minX + margin
        case .dockRight:
            x = visible.maxX - margin - effectiveWidth
        }
        let y = visible.minY + margin
        return NSRect(x: x.rounded(), y: y.rounded(), width: effectiveWidth, height: preferredSize.height)
    }

    // MARK: - Context file (width info for AI writers)

    /// Measure available panel widths and write to `hud_context.json`.
    /// Remote AI reads this to know how many characters fit in each panel.
    private func syncContextFile() {
        guard let config = activeConfig else { return }
        let watchPath = config.watchDirectory ?? {
            // Fall back to the bundled Examples directory
            Bundle.main.url(forResource: "config", withExtension: "json", subdirectory: "Examples")?
                .deletingLastPathComponent().path
        }()
        guard let watchPath, !watchPath.isEmpty else { return }
        let dir = URL(fileURLWithPath: (watchPath as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: dir.path) else { return }

        var leftWidth: CGFloat = 0
        var rightWidth: CGFloat = 0
        for managedWindow in managedWindows {
            // For rotated (side-Dock) panels the text line width is the frame height.
            let geo = dockGeometry(on: managedWindow.screen)
            let w = geo.isVertical ? managedWindow.window.frame.height : managedWindow.window.frame.width
            switch managedWindow.slot.anchor {
            case .dockLeft:  leftWidth = w
            case .dockRight: rightWidth = w
            }
        }

        // Rough char estimate: system rounded font at 13pt ≈ 7pt per char
        let context: [String: Any] = [
            "leftWidth": Int(leftWidth),
            "rightWidth": Int(rightWidth),
            "maxCharsLeft": Int(leftWidth / 7),
            "maxCharsRight": Int(rightWidth / 7),
            "maxCharsPerLine": Int(max(leftWidth, rightWidth) / 7),
            "updatedAt": ISO8601DateFormatter().string(from: Date())
        ]

        let finalURL = dir.appendingPathComponent("hud_context.json")
        if let data = try? JSONSerialization.data(withJSONObject: context, options: .prettyPrinted) {
            try? data.write(to: finalURL)
        }
    }
}
