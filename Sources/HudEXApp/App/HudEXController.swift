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
    private let remindersSync = RemindersSyncService()

    private let edgePanels = EdgePanelController()
    private let previewPanel = PreviewPanelController()
    private let detailWindow = DetailWindowController()

    // MARK: - Published state (read by Settings and the menu)

    struct GeometrySummary: Equatable {
        var edge: DockEdge = .bottom
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

        /// The Dock as the layout engine wants it, for the Settings diagram.
        var dockBounds: DockBounds {
            DockBounds(
                edge: edge,
                thickness: CGFloat(thickness),
                occupiedStart: CGFloat(occupiedStart),
                occupiedEnd: CGFloat(occupiedEnd),
                isPresent: isDockPresent
            )
        }

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
    private var pendingReminderSync: DispatchWorkItem?
    private var remindersSyncRerunPending = false
    private var remindersManualRerunPending = false
    private var midnightTimer: Timer?
    private var previewHideWorkItem: DispatchWorkItem?
    private var currentScreen: NSScreen?
    private var currentEdge: DockEdge = .bottom
    /// Edge the tabs are actually drawn on (differs from `currentEdge` in the
    /// fixed-edge layout mode). The hover card opens away from this edge.
    private var planEdge: DockEdge = .bottom
    private var tagFrames: [String: CGRect] = [:]
    private var performanceLogTimer: Timer?
    private var pendingPreferenceRefresh: DispatchWorkItem?
    private var lastAppliedStyle: AppearanceStyle?
    private var lastRenderedDay = Calendar.current.startOfDay(for: Date())
    /// The project the preview panel currently belongs to. It outlives the
    /// pointer leaving a tag, because the pointer crosses a small gap into the
    /// preview itself and the panel must not flicker shut on the way.
    private var previewProjectID: String?

    /// When the settings block in the Markdown file was last written.
    @Published private(set) var lastSettingsWrite: Date?
    @Published private(set) var remindersSyncStatus: String?
    @Published private(set) var remindersSyncing = false

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

        createStarterFileIfNeeded()

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
            if self.store.document.parsedAt != .distantPast,
               self.store.document.settings == nil, let url = self.store.sourceURL {
                self.settingsSync.scheduleWrite(to: url)
            }
            self.lastSettingsWrite = self.settingsSync.lastWriteAt
            self.scheduleAutomaticRemindersSync()
        }
        remindersSync.onStoreChanged = { [weak self] in
            self?.scheduleAutomaticRemindersSync()
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

        if let stress = ProcessInfo.processInfo.environment["HUDEX_STRESS"], let count = Int(stress) {
            // Development aid: drive the settings path as fast as a slider drag
            // would, to check that repeated re-renders do not accumulate.
            var step = 0
            Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                step += 1
                let styles = AppearanceStyle.allCases
                self.preferences.appearanceStyle = styles[step % styles.count]
                self.preferences.stackOverlap = 0.2 + Double(step % 20) * 0.02
                self.preferences.thresholdAttention = 5 + (step % 30)
                if step >= count { timer.invalidate() }
            }
        }
        if ProcessInfo.processInfo.environment["HUDEX_OPEN_FILE_PANEL"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.chooseMarkdownFile()
            }
        }
        if ProcessInfo.processInfo.environment["HUDEX_OPEN_SETTINGS"] != nil {
            // Development aid: start with the settings window open, so memory
            // and rendering behaviour can be measured without UI automation.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                SettingsWindowController.shared.show()
            }
        }
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
        pendingReminderSync?.cancel()
        pendingReminderSync = nil
        store.stop()
        edgePanels.hideAll()
        previewPanel.hide()
        Log.app.info("HudEX stopped")
    }

    // MARK: - Refresh

    private func preferencesDidChange() {
        // Visibility can change while the panels are on screen.
        edgePanels.applyVisibility(preferences.panelVisibility)
        previewPanel.hide()

        if preferences.resolvedSourceURL != store.sourceURL {
            store.configureSource(preferences.resolvedSourceURL)
        }
        scheduleAutomaticRemindersSync()
        preferencesBinding?.updateVisibility()

        // A style change is visible immediately, including on a card that is
        // already open — otherwise clicking a style looks like nothing happened.
        if preferences.appearanceStyle != lastAppliedStyle {
            lastAppliedStyle = preferences.appearanceStyle
            if let screen = currentScreen {
                previewPanel.restyle(
                    preferences.appearanceStyle,
                    screenVisibleFrame: screen.visibleFrame
                )
            }
        }

        // Dragging a slider fires many changes; coalesce them into one relayout
        // so the interaction stays smooth.
        pendingPreferenceRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.refresh(reason: "preferences", allowExpensiveProbes: false)
        }
        pendingPreferenceRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)

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

    /// Migrates the active source to one .json file without leaving a second
    /// HudEX data file beside it, refreshing the durable AI instructions.
    func makeSingleJSONSource() {
        guard let url = store.sourceURL else { return }
        let target = url.deletingPathExtension().appendingPathExtension("json")
        guard target != url else { return }
        settingsSync.cancelPendingWrite()
        do {
            guard !FileManager.default.fileExists(atPath: target.path) else {
                throw NSError(domain: "HudEX.Source", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: L10n.t("reminders.targetExists", target.path)
                ])
            }
            let fresh: HudEXDocument
            switch MarkdownDocumentLoader().load(url: url, previous: nil) {
            case .success(let loaded): fresh = loaded.document
            case .failure(let error):
                throw NSError(domain: "HudEX.Source", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: error.displayMessage
                ])
            }
            var document = fresh
            document.format = .json
            document.sourceID = document.sourceID ?? UUID().uuidString.lowercased()
            document.hudexVersion = Self.appReleaseVersion
            document.aiInstructions = HudEXJSONCodec.defaultAIInstructions
            document.schemaVersion = HudEXJSONCodec.currentVersion
            try HudEXJSONCodec.encode(document).write(to: target, options: .atomic)
            do { try FileManager.default.removeItem(at: url) }
            catch {
                try? FileManager.default.removeItem(at: target)
                throw error
            }
            setSourceURL(target)
            remindersSyncStatus = L10n.t("reminders.converted")
        } catch {
            remindersSyncStatus = error.localizedDescription
        }
    }

    func syncRemindersNow() {
        startRemindersSync(automatic: false)
    }

    private func startRemindersSync(automatic: Bool) {
        guard !remindersSyncing else {
            remindersSyncRerunPending = true
            remindersManualRerunPending = remindersManualRerunPending || !automatic
            return
        }
        guard store.document.format == .json else {
            remindersSyncStatus = L10n.t("reminders.convertFirst")
            return
        }
        guard let sourceURL = store.sourceURL else { return }
        let expectedSignature = FileSignature.read(at: sourceURL)
        remindersSyncing = true
        remindersSyncStatus = L10n.t("reminders.syncing")
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await self.remindersSync.sync(
                    document: self.store.document,
                    appVersion: Self.appReleaseVersion
                )
                switch self.store.saveSynchronizedJSON(result.document, expectedSignature: expectedSignature) {
                case .failed(let message):
                    self.remindersSyncStatus = L10n.t("reminders.saveFailed", message)
                case .written, .unchanged:
                    var statusParts: [String] = []
                    if result.createdProjects > 0 {
                        statusParts.append(L10n.t("reminders.projectsCreated", result.createdProjects))
                    }
                    if result.projectCommandConflicts > 0 {
                        statusParts.append(L10n.t("reminders.projectConflict", result.projectCommandConflicts))
                    }
                    if !result.projectCommandIdentifiers.isEmpty {
                        do {
                            try await self.remindersSync.consumeProjectCommands(
                                identifiers: result.projectCommandIdentifiers
                            )
                        } catch {
                            statusParts.append(L10n.t("reminders.projectCommandCleanupFailed"))
                        }
                    }
                    let cleanup = await self.remindersSync.cleanupLegacyLists()
                    if cleanup.removed > 0 {
                        statusParts.append(L10n.t("reminders.synced.cleaned", cleanup.removed))
                    }
                    if cleanup.retained > 0 {
                        statusParts.append(L10n.t("reminders.synced.retained", cleanup.retained))
                    }
                    self.remindersSyncStatus = statusParts.isEmpty
                        ? L10n.t("reminders.synced")
                        : statusParts.joined(separator: " ")
                }
            } catch {
                self.remindersSyncStatus = error.localizedDescription
            }
            self.remindersSyncing = false
            if self.remindersSyncRerunPending {
                let manualRerun = self.remindersManualRerunPending
                let automaticRerun = self.preferences.remindersAutoSyncEnabled
                self.remindersSyncRerunPending = false
                self.remindersManualRerunPending = false
                guard manualRerun || automaticRerun else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    guard let self else { return }
                    self.startRemindersSync(automatic: !manualRerun)
                }
            }
        }
    }

    private func scheduleAutomaticRemindersSync() {
        guard preferences.remindersAutoSyncEnabled,
              store.document.format == .json,
              !store.isLoading,
              store.sourceURL != nil else {
            pendingReminderSync?.cancel()
            pendingReminderSync = nil
            return
        }
        pendingReminderSync?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.preferences.remindersAutoSyncEnabled else { return }
            self.startRemindersSync(automatic: true)
        }
        pendingReminderSync = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
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

        planEdge = plan.edge
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
            // Includes rotation, layering and the hover lift: a tag whose
            // rounded corners used to be clipped now always fits.
            let box = EdgeLayoutEngine.panelBounds(
                for: placements,
                metrics: plan.metrics,
                edge: plan.edge
            )

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
                    priority: project.priority,
                    size: placement.frame.size,
                    screenFrame: placement.frame,
                    localFrame: localFrame,
                    rotationDegrees: placement.rotationDegrees,
                    hoverOffset: placement.hoverOffset,
                    zIndex: Double(placement.zIndex),
                    isHovered: hoveredProjectID == project.id
                )
            }

            models[slot] = EdgePanelModel(
                edge: plan.edge,
                style: preferences.appearanceStyle,
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
        summary.edge = bounds.edge
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
        resolveDocumentWaiters()
    }

    /// Runs `body` once the first document load has finished (immediately when it
    /// already has). Startup decisions must not guess at this: the read is
    /// asynchronous, and a fixed delay is a race.
    func whenDocumentResolved(_ body: @escaping (Bool) -> Void) {
        if documentResolved {
            body(hasUsableDocument)
            return
        }
        documentWaiters.append(body)
    }

    private func resolveDocumentWaiters() {
        guard !documentResolved else { return }
        guard store.loadAttempts > 0 else { return }
        documentResolved = true
        let usable = hasUsableDocument
        let waiters = documentWaiters
        documentWaiters.removeAll()
        waiters.forEach { $0(usable) }
    }

    private var documentResolved = false
    private var documentWaiters: [(Bool) -> Void] = []

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
            holeEdgePoint: paintedEdgePoint(forProject: projectID),
            edge: planEdge,
            style: preferences.appearanceStyle,
            screenVisibleFrame: screen.visibleFrame,
            seed: Self.stringSeed(for: projectID)
        )
    }

    /// Stable per-project seed: each string hangs differently, but always the
    /// same way for the same project.
    static func stringSeed(for projectID: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in projectID.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    /// True while HudEX should be introducing itself: the first launch of a
    /// fresh install (so the person sees where the file went and picks a look),
    /// or any time there is no usable document. Afterwards the pane disappears
    /// and Settings opens on General like it does for everyone else.
    var needsOnboarding: Bool { isFirstRunSession || !hasUsableDocument }

    /// Set for the duration of the very first launch.
    var isFirstRunSession = false

    /// Whether there is a document worth showing: the file exists and at least
    /// one project parsed out of it.
    var hasUsableDocument: Bool {
        (documentSummary.projectCount > 0 || store.document.format == .json) && FileManager.default.fileExists(
            atPath: documentSummary.path
        )
    }

    /// Remembers that the last launch was interrupted, and why it matters.
    func noteRecoveredLaunch(attempts: Int, report: URL?) {
        recoveredLaunch = (attempts, report)
        Log.app.warning("recovered from \(attempts) interrupted launch(es)")
        refresh(reason: "safemode", allowExpensiveProbes: false)
    }

    /// Shown in Settings when the guard had to clean up.
    private(set) var recoveredLaunch: (attempts: Int, report: URL?)?

    /// Dismisses the recovery notice (the report file itself is removed by the
    /// settings pane).
    func clearRecoveredLaunch() {
        recoveredLaunch = nil
    }

    /// Asks the user for the Markdown or JSON source file. The panel is created per call and
    /// dropped immediately: keeping one alive (or keeping its URLs) pins the
    /// directory listing, icons and QuickLook previews in memory.
    func chooseMarkdownFile() {
        let panel = NSOpenPanel()
        panel.title = L10n.t("source.panel.title")
        panel.prompt = L10n.t("source.panel.prompt")
        panel.allowedContentTypes = [
            .init(filenameExtension: "md") ?? .plainText,
            .init(filenameExtension: "json") ?? .plainText,
            .plainText
        ]
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.showsTagField = false
        panel.isAccessoryViewDisclosed = false
        // No QuickLook preview: the preview generator is a separate service and
        // its caches are what made the process look heavy after using the picker.
        panel.directoryURL = URL(fileURLWithPath: documentSummary.path).deletingLastPathComponent()

        let response = panel.runModal()
        let url = panel.url
        panel.orderOut(nil)
        if response == .OK, let url {
            setSourceURL(url)
        }
    }

    /// The exact point where the hovered tag's card-facing edge crosses its
    /// centre line, painted state included. The string starts there, which is
    /// what removes the last pixel of gap between tag and line.
    private func paintedEdgePoint(forProject id: String) -> CGPoint? {
        guard let tag = edgePanels.tagModel(forProject: id) else { return nil }
        return EdgeLayoutEngine.paintedEdgePoint(
            of: TagPlacement(
                index: tag.index,
                slot: .primary,
                frame: tag.screenFrame,
                rotationDegrees: tag.rotationDegrees,
                zIndex: Int(tag.zIndex),
                hoverOffset: tag.hoverOffset
            ),
            edge: planEdge,
            hovered: tag.isHovered
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

    /// A first launch with nothing configured gets a file in HudEX's own folder
    /// straight away — that folder needs no authorisation, so the bookmarks have
    /// something to show before the person has decided anything. Once a source
    /// has been chosen, this never runs again: a missing file the user pointed at
    /// stays missing (and is reported), rather than being silently recreated.
    private func createStarterFileIfNeeded() {
        guard preferences.sourcePath.isEmpty else { return }
        if let existing = SourceLocator.firstExisting(candidates: SourceLocator.candidates()) {
            store.configureSource(existing)
            return
        }
        let url = Preferences.defaultSourceURL
        _ = createExampleFile(at: url, openAfterwards: false)
    }

    func createExampleFile(at url: URL, openAfterwards: Bool = true) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if url.pathExtension.lowercased() == "json" {
                var document = MarkdownProjectParser().parse(HudEXTemplate.markdown())
                document.format = .json
                document.sourceID = UUID().uuidString.lowercased()
                document.aiInstructions = HudEXJSONCodec.defaultAIInstructions
                document.schemaVersion = HudEXJSONCodec.currentVersion
                try HudEXJSONCodec.encode(document).write(to: url, options: .atomic)
            } else {
                try HudEXTemplate.markdown().write(to: url, atomically: true, encoding: .utf8)
            }
            Log.markdown.info("created example document at \(url.path, privacy: .public)")
            store.configureSource(url)
            store.reload(reason: "example created")
            if openAfterwards {
                ExternalOpenService.openFile(url)
            }
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

    static var appReleaseVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.6"
    }

    var diagnosticsText: String {
        var lines: [String] = []
        lines.append(L10n.t("diagnostics.title", Self.version))
        lines.append(L10n.t("diagnostics.system", ProcessInfo.processInfo.operatingSystemVersionString))
        lines.append(L10n.t("diagnostics.source", documentSummary.path))
        let crashes = LaunchGuard.crashReports()
        lines.append(
            L10n.t("diagnostics.crashReports", crashes.isEmpty ? L10n.t("common.none") : crashes.joined(separator: ", "))
        )
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
