import AppKit
import Combine
import HudEXCore
import SwiftUI

/// The coordinator: it owns the document store, the Dock geometry, the edge
/// layout and the three windows, and it is the only place that decides what is
/// on screen.
///
/// Everything it does is event driven: screen changes, Space changes, wake,
/// Dock preference changes and file system events. There is no poll timer. The
/// only time-based work is a single timer scheduled just after midnight (for
/// the colour rollover) and — only while it is actually on screen — the
/// preview's once-a-minute age refresh.
@MainActor
final class HudEXController: ObservableObject {
    static let shared = HudEXController()

    // MARK: - Collaborators

    let preferences: Preferences

    /// The menu bar item, told about preference changes that affect it. Weak so
    /// the status item can be released normally at termination.
    weak var preferencesBinding: StatusItemController?
    let store: DocumentStore
    let dockProvider: DockGeometryProvider
    let launchAtLogin: LaunchAtLoginService
    private let settingsSync: SettingsSync

    private let edgePanels = EdgePanelController()
    private let previewPanel = PreviewPanelController()
    private let detailWindow = DetailWindowController()

    // MARK: - Published state (read by Settings and the menu)

    struct GeometrySummary: Equatable {
        var edgeName: String = "—"
        var thickness: Int = 0
        var occupiedStart: Int = 0
        var occupiedEnd: Int = 0
        var sourceName: String = "—"
        var isDockPresent = false
        var isDockVisible = true
        var screenName: String = "—"
        var primaryRange: String = "—"
        var secondaryRange: String = "—"
        var primaryCapacity: Int = 0
        var secondaryCapacity: Int = 0

        static let empty = GeometrySummary()
    }

    struct DocumentSummary: Equatable {
        var path: String = "—"
        var projectCount = 0
        var loadedAt: Date?
        var statusMessage: String?
        var errorMessage: String?
        var warnings: [String] = []
    }

    @Published private(set) var geometry: GeometrySummary = .empty
    @Published private(set) var documentSummary = DocumentSummary()
    @Published private(set) var overflowCount = 0
    @Published private(set) var hoveredProjectID: String?

    // MARK: - Private state

    private var started = false
    private var observerTokens: [NSObjectProtocol] = []
    private var preferencesObserver: AnyCancellable?
    private var midnightTimer: Timer?
    private var previewHideWorkItem: DispatchWorkItem?
    private var currentScreen: NSScreen?
    private var currentEdge: DockEdge = .bottom
    private var tagFrames: [String: CGRect] = [:]
    private var performanceLogTimer: Timer?
    private var lastRenderedDay = Calendar.current.startOfDay(for: Date())
    /// The project the preview panel currently belongs to. It outlives the
    /// pointer leaving a tag, because the pointer crosses a small gap into the
    /// preview itself and the panel must not flicker shut on the way.
    private var previewProjectID: String?

    /// When the settings block in the Markdown file was last written.
    @Published private(set) var lastSettingsWrite: Date?

    private init() {
        preferences = Preferences.shared
        store = DocumentStore()
        dockProvider = DockGeometryProvider()
        launchAtLogin = LaunchAtLoginService.shared
        settingsSync = SettingsSync(preferences: Preferences.shared)
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        Log.app.info("HudEX \(Self.version, privacy: .public) starting")

        store.onDocumentChanged = { [weak self] in
            guard let self else { return }
            // The file is the source of truth for settings too: anything it
            // carries is applied before the layout is rebuilt.
            if self.settingsSync.apply(from: self.store.document) {
                Log.debug(Log.settings, "settings applied from the Markdown file")
            }
            self.refresh(reason: "document", allowExpensiveProbes: false)
            // A file without the block gets one, so the settings (and the guide
            // lines an AI needs) are always documented in the file itself.
            if self.store.document.settings == nil, let url = self.store.sourceURL {
                self.settingsSync.scheduleWrite(to: url)
            }
            self.lastSettingsWrite = self.settingsSync.lastWriteAt
        }
        edgePanels.onHoverChange = { [weak self] id in
            self?.handleHover(id)
        }
        previewPanel.onPointerEnter = { [weak self] in self?.cancelPreviewHide() }
        previewPanel.onPointerExit = { [weak self] in self?.schedulePreviewHide() }
        previewPanel.onRefreshTick = { [weak self] in self?.refreshPreviewContent() }
        detailWindow.setEditAction { [weak self] in self?.openMarkdownFile() }

        preferencesObserver = preferences.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.preferencesDidChange()
            }
        }

        observerTokens.append(
            NotificationCenter.default.addObserver(
                forName: L10n.languageDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refresh(reason: "language", allowExpensiveProbes: false) }
            }
        )

        installObservers()
        performanceLogTimer = PerformanceMonitor.startLoggingIfRequested()
        scheduleMidnightRefresh()
        launchAtLogin.refresh()

        store.start(url: preferences.resolvedSourceURL)
        refresh(reason: "launch", allowExpensiveProbes: true)
    }

    func stop() {
        guard started else { return }
        started = false
        performanceLogTimer?.invalidate()
        performanceLogTimer = nil
        midnightTimer?.invalidate()
        midnightTimer = nil
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            DistributedNotificationCenter.default().removeObserver(token)
        }
        observerTokens.removeAll()
        previewHideWorkItem?.cancel()
        store.stop()
        edgePanels.hideAll()
        previewPanel.hide()
        Log.app.info("HudEX stopped")
    }

    // MARK: - Refresh

    private func preferencesDidChange() {
        if preferences.resolvedSourceURL != store.sourceURL {
            store.configureSource(preferences.resolvedSourceURL)
        }
        preferencesBinding?.updateVisibility()
        refresh(reason: "preferences", allowExpensiveProbes: false)
        // Reflect the change back into the Markdown block, debounced.
        if let url = store.sourceURL {
            settingsSync.scheduleWrite(to: url)
        }
    }

    // MARK: - Settings sync

    /// Writes the current settings into the Markdown file right away.
    func writeSettingsToMarkdown() {
        guard let url = store.sourceURL else { return }
        settingsSync.writeNow(to: url)
        lastSettingsWrite = settingsSync.lastWriteAt
    }

    /// Re-reads the settings block from the file, ignoring the write debounce.
    func applySettingsFromMarkdown() {
        store.reload(reason: "settings re-read")
    }

    /// Recomputes everything that depends on the document, the Dock and the
    /// screen, then pushes a fresh value model into the panels.
    func refresh(reason: String, allowExpensiveProbes: Bool) {
        guard started else { return }

        guard preferences.showTags else {
            edgePanels.hideAll()
            previewPanel.hide()
            tagFrames.removeAll()
            if overflowCount != 0 { overflowCount = 0 }
            updateDocumentSummary()
            return
        }

        guard let screen = ScreenGeometry.dockScreen() else {
            Log.app.warning("no screen available")
            return
        }
        currentScreen = screen
        currentEdge = dockProvider
            .snapshot(for: screen, allowExpensiveProbes: allowExpensiveProbes)
            .bounds.edge

        let snapshot = dockProvider.snapshot(for: screen, allowExpensiveProbes: allowExpensiveProbes)
        let screenBounds = ScreenGeometry.bounds(of: screen)
        let metrics = TabMetrics.make(
            dockThickness: snapshot.bounds.thickness,
            fontSizeOverride: preferences.fontSizeOverride,
            protrusionOverride: preferences.tagProtrusionOverride,
            lengthOverride: preferences.tabLengthOverride,
            edgeGap: preferences.edgeGap,
            cornerInset: preferences.cornerInset,
            stack: preferences.stackStyle
        )

        let projects = store.document.projects
        let plan = EdgeLayoutEngine.plan(
            projectCount: projects.count,
            metrics: metrics,
            screen: screenBounds,
            dock: snapshot.bounds,
            limits: preferences.tagLimits,
            mode: preferences.layoutMode
        )

        let models = buildPanelModels(plan: plan, projects: projects)
        edgePanels.update(models)
        tagFrames = models.values
            .flatMap { $0.tags }
            .reduce(into: [:]) { partial, tag in partial[tag.id] = tag.screenFrame }

        updateGeometrySummary(plan: plan, snapshot: snapshot, screen: screen)
        updateDocumentSummary()

        if overflowCount != plan.overflowCount {
            overflowCount = plan.overflowCount
            if plan.overflowCount > 0 {
                Log.layout.warning("\(plan.overflowCount) project(s) do not fit next to the Dock")
            }
        }

        Log.debug(Log.layout, "layout refreshed (\(reason)): \(projects.count) projects, \(plan.placements.count) tabs")
        Log.trace("refresh(\(reason)) edge=\(snapshot.bounds.edge.rawValue) thickness=\(Int(snapshot.bounds.thickness)) occupied=\(Int(snapshot.bounds.occupiedStart))-\(Int(snapshot.bounds.occupiedEnd)) source=\(snapshot.bounds.source.rawValue) placements=\(plan.placements.map { String(format: "(%.0f,%.0f %.0fx%.0f)", $0.frame.minX, $0.frame.minY, $0.frame.width, $0.frame.height) }.joined(separator: " "))")
    }

    private func buildPanelModels(
        plan: EdgeLayoutPlan,
        projects: [HudEXProject]
    ) -> [EdgeSlot: EdgePanelModel] {
        guard !projects.isEmpty else { return [:] }
        let now = Date()
        let thresholds = preferences.colorThresholds
        var models: [EdgeSlot: EdgePanelModel] = [:]

        for slot in EdgeSlot.allCases {
            let placements = plan.placements.filter { $0.slot == slot }
            guard !placements.isEmpty else { continue }
            let box = placements.reduce(CGRect.null) { $0.union($1.frame) }

            let tags: [EdgeTagModel] = placements.map { placement in
                let project = projects[placement.index]
                let role = TagColorPolicy.role(
                    status: project.status,
                    updatedAt: store.document.ageReferenceDate(for: project),
                    now: now,
                    thresholds: thresholds
                )
                // Flip into SwiftUI's top-left origin inside the panel.
                let localFrame = CGRect(
                    x: placement.frame.minX - box.minX,
                    y: box.maxY - placement.frame.maxY,
                    width: placement.frame.width,
                    height: placement.frame.height
                )
                return EdgeTagModel(
                    id: project.id,
                    index: placement.index,
                    shortTitle: project.shortTitle,
                    title: project.title,
                    role: role,
                    colorOverride: project.colorOverride,
                    size: placement.frame.size,
                    screenFrame: placement.frame,
                    localFrame: localFrame,
                    rotationDegrees: placement.rotationDegrees,
                    stagger: plan.metrics.stack.isEnabled ? plan.metrics.stack.stagger : 0,
                    zIndex: Double(placement.zIndex),
                    isHovered: hoveredProjectID == project.id
                )
            }

            models[slot] = EdgePanelModel(
                edge: plan.edge,
                fontSize: plan.metrics.fontSize,
                screenFrame: box,
                size: box.size,
                tags: tags
            )
        }
        return models
    }

    private func updateGeometrySummary(
        plan: EdgeLayoutPlan,
        snapshot: DockGeometryProvider.Snapshot,
        screen: NSScreen
    ) {
        let bounds = snapshot.bounds
        var summary = GeometrySummary()
        summary.edgeName = L10n.t(bounds.edge.displayNameKey)
        summary.thickness = Int(bounds.thickness.rounded())
        summary.occupiedStart = Int(bounds.occupiedStart.rounded())
        summary.occupiedEnd = Int(bounds.occupiedEnd.rounded())
        summary.sourceName = L10n.t(bounds.source.displayNameKey)
        summary.isDockPresent = bounds.isPresent
        summary.isDockVisible = bounds.isVisible
        summary.screenName = screen.localizedName

        if let range = plan.slotRanges[.primary] {
            summary.primaryRange = "\(Int(range.lowerBound.rounded()))–\(Int(range.upperBound.rounded())) pt"
            summary.primaryCapacity = EdgeLayoutEngine.capacity(in: range, metrics: plan.metrics)
        } else {
            summary.primaryRange = L10n.t("diagnostics.unavailable")
            summary.primaryCapacity = 0
        }
        if let range = plan.slotRanges[.secondary] {
            summary.secondaryRange = "\(Int(range.lowerBound.rounded()))–\(Int(range.upperBound.rounded())) pt"
            summary.secondaryCapacity = EdgeLayoutEngine.capacity(in: range, metrics: plan.metrics)
        } else {
            summary.secondaryRange = L10n.t("diagnostics.unavailable")
            summary.secondaryCapacity = 0
        }

        if geometry != summary {
            geometry = summary
        }
    }

    private func updateDocumentSummary() {
        var summary = DocumentSummary()
        summary.path = (store.sourceURL ?? preferences.resolvedSourceURL).path
        summary.projectCount = store.document.projects.count
        summary.loadedAt = store.lastLoadedAt
        summary.statusMessage = store.statusMessage
        summary.errorMessage = store.lastError
        summary.warnings = store.document.diagnostics
            .filter { $0.severity != .info }
            .prefix(6)
            .map { diagnostic in
                if let line = diagnostic.line {
                    return "第 \(line) 行：\(diagnostic.message)"
                }
                return diagnostic.message
            }
        if documentSummary != summary {
            documentSummary = summary
        }
    }

    // MARK: - Hover

    private func handleHover(_ id: String?) {
        if hoveredProjectID != id {
            hoveredProjectID = id
            // Re-render the tabs so the hovered one can lift out of the stack.
            // Cheap: the Dock geometry is cached and only the view values change.
            refresh(reason: "hover", allowExpensiveProbes: false)
        }
        guard let id else {
            // The pointer left the tabs. It may be on its way into the preview,
            // so only schedule the hide and keep the preview target alive.
            schedulePreviewHide()
            return
        }
        cancelPreviewHide()
        previewProjectID = id
        showPreview(for: id)
    }

    private func showPreview(for projectID: String) {
        guard let project = store.document.project(id: projectID),
              let tagFrame = tagFrames[projectID],
              let screen = currentScreen else { return }

        let model = PreviewModel.make(
            project: project,
            document: store.document,
            preferences: preferences
        )
        previewPanel.show(
            model: model,
            tagFrame: tagFrame,
            edge: currentEdge,
            screenVisibleFrame: screen.visibleFrame
        )
    }

    private func refreshPreviewContent() {
        guard let id = previewProjectID, previewPanel.isVisible else { return }
        guard let project = store.document.project(id: id) else { return }
        previewPanel.refresh(
            model: PreviewModel.make(project: project, document: store.document, preferences: preferences)
        )
    }

    private func schedulePreviewHide() {
        previewHideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.previewPanel.hide()
            self.previewProjectID = nil
            if self.hoveredProjectID != nil { self.hoveredProjectID = nil }
        }
        previewHideWorkItem = work
        // A short grace period lets the pointer travel from the tab into the
        // preview without the window flickering away.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
    }

    private func cancelPreviewHide() {
        previewHideWorkItem?.cancel()
        previewHideWorkItem = nil
    }

    // MARK: - Actions

    func openMarkdownFile() {
        let url = store.sourceURL ?? preferences.resolvedSourceURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            createExampleFile(at: url)
            return
        }
        if !ExternalOpenService.openFile(url) {
            Log.markdown.warning("no application accepted \(url.path, privacy: .public)")
        }
    }

    func revealInFinder() {
        ExternalOpenService.revealInFinder(store.sourceURL ?? preferences.resolvedSourceURL)
    }

    func reloadDocument() {
        store.reload(reason: "manual")
    }

    func openSettings() {
        SettingsOpener.open()
    }

    /// The one settings window instance (also used as the recovery path when
    /// the Menu Bar icon is switched off).
    func settingsWindow() -> SettingsWindowController {
        SettingsWindowController.shared
    }

    /// Opens the full project text. Reached from a tag's context menu, so the
    /// project is identified explicitly instead of relying on hover state.
    func openDetail(projectID: String) {
        guard let project = store.document.project(id: projectID) else { return }
        previewPanel.hide()
        detailWindow.show(
            model: DetailModel.make(project: project, document: store.document, preferences: preferences),
            title: project.title
        )
    }

    func setSourceURL(_ url: URL) {
        preferences.setSourceURL(url)
        store.configureSource(url)
        refresh(reason: "source changed", allowExpensiveProbes: true)
    }

    /// Writes the example document, used by Settings when no `HudEX.md` exists.
    @discardableResult
    func createExampleFile(at url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try HudEXTemplate.markdown().write(to: url, atomically: true, encoding: .utf8)
            Log.markdown.info("created example document at \(url.path, privacy: .public)")
            store.configureSource(url)
            store.reload(reason: "example created")
            ExternalOpenService.openFile(url)
            return true
        } catch {
            Log.markdown.error("could not create \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func resetDockGeometryCache() {
        dockProvider.resetCache()
        refresh(reason: "cache cleared", allowExpensiveProbes: true)
    }

    // MARK: - Environment changes

    private func installObservers() {
        let center = NotificationCenter.default
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        observerTokens.append(
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.environmentDidChange(reason: "screen parameters") }
            }
        )

        observerTokens.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.environmentDidChange(reason: "active space") }
            }
        )

        observerTokens.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.dockProvider.invalidatePreferences()
                    self.store.reloadIfChanged(reason: "wake")
                    self.scheduleMidnightRefresh()
                    self.refresh(reason: "wake", allowExpensiveProbes: true)
                }
            }
        )

        observerTokens.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.sessionDidBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.environmentDidChange(reason: "session active") }
            }
        )

        observerTokens.append(
            distributed.addObserver(
                forName: Notification.Name("com.apple.dock.prefchanged"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.environmentDidChange(reason: "dock preferences") }
            }
        )
    }

    private func environmentDidChange(reason: String) {
        dockProvider.invalidatePreferences()
        store.rearmWatcherIfNeeded()
        refresh(reason: reason, allowExpensiveProbes: true)
    }

    // MARK: - Time-based refresh

    /// HudEX deliberately has no repeating poll timer. The Dock, the screens and
    /// the Spaces are all event driven, and the only time-based work left is a
    /// single timer scheduled for just after midnight (the colour rollover) plus
    /// the optional performance log.

    private func scheduleMidnightRefresh() {
        midnightTimer?.invalidate()
        let calendar = Calendar.current
        guard let next = calendar.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 1),
            matchingPolicy: .nextTime
        ) else { return }

        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.lastRenderedDay = Calendar.current.startOfDay(for: Date())
                self?.refresh(reason: "midnight", allowExpensiveProbes: false)
                self?.scheduleMidnightRefresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        midnightTimer = timer
    }

    // MARK: - Diagnostics

    /// Live resource usage, read on demand by the Advanced pane.
    var performance: PerformanceSnapshot { PerformanceMonitor.sample() }

    static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var diagnosticsText: String {
        var lines: [String] = []
        lines.append(L10n.t("diagnostics.title", Self.version))
        lines.append(L10n.t("diagnostics.system", ProcessInfo.processInfo.operatingSystemVersionString))
        lines.append(L10n.t("diagnostics.source", documentSummary.path))
        lines.append(L10n.t("diagnostics.projects", documentSummary.projectCount))
        lines.append(L10n.t("diagnostics.edge", geometry.edgeName))
        lines.append(L10n.t("diagnostics.thickness", geometry.thickness))
        lines.append(L10n.t("diagnostics.occupied", geometry.occupiedStart, geometry.occupiedEnd))
        lines.append(L10n.t("diagnostics.sourceOfTruth", geometry.sourceName))
        lines.append(L10n.t("diagnostics.primary", geometry.primaryRange, geometry.primaryCapacity))
        lines.append(L10n.t("diagnostics.secondary", geometry.secondaryRange, geometry.secondaryCapacity))
        lines.append(L10n.t("diagnostics.screen", geometry.screenName))
        lines.append(L10n.t("diagnostics.overflow", overflowCount))
        if let loadedAt = documentSummary.loadedAt {
            lines.append(L10n.t("diagnostics.loadedAt", TimestampFormatter.string(from: loadedAt)))
        }
        if let error = documentSummary.errorMessage {
            lines.append(L10n.t("diagnostics.error", error))
        }
        return lines.joined(separator: "\n")
    }
}
