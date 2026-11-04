import AppKit
import TrrekAppCore
import TrrekEngine
import TrrekPlatform

/// Connects settings, the gesture engine and the platform bridges, and owns them for the app's lifetime.
///
/// Every engine call goes through `GesturePipeline.withEngine`. Observer and input callbacks arrive on the
/// main thread and are handled on the main actor.
@MainActor
final class Coordinator {
    /// How long wake and device notifications must stay quiet before the multitouch stream restarts.
    static let restartDelay: TimeInterval = 0.4

    let windows = WindowRegistry()
    private lazy var settingsWindowController = SettingsWindowController(registry: windows)
    private lazy var welcomeWindowController = WelcomeWindowController(registry: windows)
    /// Shown by the dispatcher for levels the system shows no indicator for.
    let overlay = OverlayPanel()
    private let store: SettingsStore

    private(set) var settings = Settings()
    var holdKeyTracker = HoldKeyTracker(key: .none, mode: .hold)
    var isTrusted = false
    var trackpadIssue: TrackpadIssue?
    /// The application whose pause state applies; trrek's own windows coming to the front do not change it.
    var frontmostPause = FrontmostPause()

    let freezer = CursorFreezerSlot()
    /// Routes haptics to the trackpad that slid; its actuators are rebuilt whenever the pipeline starts.
    var haptics: DeviceHaptics?
    private var backlight: KeyboardBacklight?
    /// Whether the DDC/CI bridge could be created (its system symbols were found).
    private var externalBrightnessAvailable = false
    /// Retained here: the engine only holds its sink weakly.
    var dispatcher: CommandDispatcher?
    var pipeline: GesturePipeline?
    var inputMonitor: InputMonitor?
    let frontmostObserver = FrontmostObserver()
    let wakeObserver = WakeObserver()
    let hotplugObserver = DeviceHotplugObserver()
    /// The pending multitouch restart; wake and device notifications that arrive together share one.
    var restartWork: DispatchWorkItem?
    var statusMenu: StatusMenu?
    /// Whether the system Accessibility prompt was requested during this session.
    private var accessibilityPrompted = false

    init(store: SettingsStore) {
        self.store = store
    }

    // MARK: - Lifecycle

    /// Loads the settings and starts everything. `skipFirstRun` records the welcome window as shown and shows no
    /// welcome window at launch (for screenshots and footprint checks).
    func start(skipFirstRun: Bool = false) {
        settings = store.load()
        let trusted = Permissions.isTrusted
        isTrusted = trusted
        appLogger.info("accessibility trusted: \(trusted, privacy: .public)")
        Permissions.onChange = { [weak self] trusted in
            MainActor.assumeIsolated { self?.trustChanged(trusted) }
        }
        Permissions.startObserving()

        // Each trackpad's actuator is opened when the pipeline starts (`startPipeline`), from its device list.
        let haptics = DeviceHaptics(fallback: SystemHaptics())
        self.haptics = haptics
        let backlight = KeyboardBacklight()
        self.backlight = backlight
        appLogger.info("keyboard backlight available: \(backlight != nil, privacy: .public)")
        freezer.replace(with: EventTapGuard())
        let dispatcher = makeDispatcher(haptics: haptics, backlight: backlight)
        let config = engineConfig()
        let engine = GestureEngine(config: config, sink: dispatcher)
        self.dispatcher = dispatcher
        let pipeline = GesturePipeline(engine: engine)
        pipeline.onDataUnavailable = { [weak self] _ in
            MainActor.assumeIsolated { self?.trackpadDataUnavailable() }
        }
        self.pipeline = pipeline

        rebuildHoldKeyTracker()
        frontmostPause.activated(
            bundleID: FrontmostObserver.currentBundleID,
            isOwnApp: FrontmostObserver.isOwnAppFrontmost
        )
        updatePause()
        startPipeline()
        startInputMonitor()
        startObservers()
        statusMenu = StatusMenu(coordinator: self)

        if skipFirstRun {
            if !settings.welcomeShown {
                var updated = settings
                updated.welcomeShown = true
                apply(updated)
            }
        } else if !settings.welcomeShown {
            firstRun()
        } else if !trusted {
            // A later launch without Accessibility (revoked, or reset by a reinstall) explains it again.
            showWelcome()
        }
    }

    /// Releases anything held down and stops every tap and the multitouch stream.
    func terminate() {
        restartWork?.cancel()
        restartWork = nil
        inputMonitor?.stop()
        // Frames stop first, so nothing can press Command again after it is released.
        pipeline?.stop()
        dispatcher?.releaseAll()
        frontmostObserver.stop()
        wakeObserver.stop()
        hotplugObserver.stop()
        Permissions.onChange = nil
    }

    // MARK: - Settings

    /// Stores `newSettings` and applies them to the engine and the bridges.
    func apply(_ newSettings: Settings) {
        let previous = settings
        settings = newSettings
        store.save(newSettings)
        let config = engineConfig()
        pipeline?.withEngine { $0.update(config: config) }
        dispatcher?.hapticStrength = newSettings.hapticStrength
        dispatcher?.externalBrightnessEnabled = newSettings.externalMonitorBrightness
        if previous.holdKey != newSettings.holdKey || previous.holdKeyMode != newSettings.holdKeyMode {
            rebuildHoldKeyTracker()
        }
        if previous.launchAtLogin != newSettings.launchAtLogin {
            setLaunchAtLogin(newSettings.launchAtLogin)
        }
        updatePause()
        statusMenu?.refresh()
        windows.settingsModel?.refresh(from: newSettings)
        windows.welcomeModel?.settings = newSettings
    }

    func engineConfig() -> EngineConfig {
        ConfigMapper.engineConfig(
            from: settings,
            backlightAvailable: backlight?.isAvailable ?? false,
            accessibilityTrusted: isTrusted
        )
    }

    // MARK: - State shown in the menu

    /// The application the pause state, the status line and the Pause/Resume menu item refer to: the frontmost
    /// application, or while trrek itself is in front the one before it. `nil` when it has no bundle ID.
    var pauseTargetApp: (bundleID: String, name: String)? {
        guard let id = frontmostPause.bundleID else { return nil }
        let name = NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.localizedName ?? id
        return (id, name)
    }

    /// Whether the hold key works as a toggle and is currently switched on.
    var isHoldToggleActive: Bool {
        settings.holdKey != .none && settings.holdKeyMode == .toggle && holdKeyTracker.isSatisfied
    }

    var statusText: String {
        let pausedAppName = frontmostPause.isPaused(in: settings.pausedBundleIDs) ? pauseTargetApp?.name : nil
        return StatusText.text(
            trackpadIssue: trackpadIssue,
            accessibilityTrusted: isTrusted,
            pausedAppName: pausedAppName
        )
    }

    // MARK: - Menu actions

    func pauseInFrontApp() {
        guard let id = frontmostPause.bundleID, !settings.pausedBundleIDs.contains(id) else { return }
        var updated = settings
        updated.pausedBundleIDs.append(id)
        apply(updated)
    }

    func resumeInFrontApp() {
        guard let id = frontmostPause.bundleID else { return }
        var updated = settings
        updated.pausedBundleIDs.removeAll { $0 == id }
        apply(updated)
    }

    /// Opens the settings window, or brings it to the front, on `tab` when it names one ("general", "edges",
    /// "corners", "advanced").
    func openSettings(tab: String? = nil) {
        if windows.settingsModel == nil {
            syncLaunchAtLogin()
        }
        let model = windows.settingsModel ?? SettingsModel(
            settings: settings,
            backlightAvailable: backlight?.isAvailable ?? false,
            externalBrightnessAvailable: externalBrightnessAvailable,
            accessibilityGranted: isTrusted,
            onChange: { [weak self] in self?.apply($0) }
        )
        if let tab = SettingsTab(argument: tab) {
            model.selectedTab = tab
        }
        settingsWindowController.show(model: model)
    }

    /// Opens the settings window and asks whether to import the settings file at `url` (opened from Finder). While
    /// the window already shows an alert, a sheet or is reading another file, the window comes to the front and the
    /// file is ignored (see `SettingsModel.openedFile(at:)`).
    func openSettingsFile(at url: URL) {
        let busy = windows.settingsModel?.isBusyForOpenedFile ?? false
        openSettings(tab: busy ? nil : SettingsTab.general.rawValue)
        guard let model = windows.settingsModel else { return }
        Task { await model.openedFile(at: url) }
    }

    /// Opens the welcome window, or brings it to the front.
    func showWelcome() {
        let model = windows.welcomeModel ?? WelcomeModel(
            settings: settings,
            backlightAvailable: backlight?.isAvailable ?? false,
            accessibilityGranted: isTrusted,
            grantAccessibility: { [weak self] in self?.grantAccessibility() },
            openSettings: { [weak self] in self?.openSettings() }
        )
        welcomeWindowController.show(model: model)
    }

    /// Shows the level overlay once, as a slide on the keyboard backlight would (for screenshots).
    func showDemoOverlay() {
        overlay.show(kind: .keyboardBacklight, level: 0.5, label: nil)
    }

    /// The first request shows the system prompt only. The system shows that prompt once per app, so a later
    /// request while still untrusted opens the Accessibility pane instead of doing nothing.
    func grantAccessibility() {
        let promptedBefore = accessibilityPrompted
        accessibilityPrompted = true
        Permissions.prompt()
        guard promptedBefore, !Permissions.isTrusted, let url = Permissions.accessibilityPaneURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Helpers

    /// Pauses the engine while the frontmost application (the one before trrek, while trrek is in front) is in the
    /// paused list.
    func updatePause() {
        let paused = frontmostPause.isPaused(in: settings.pausedBundleIDs)
        pipeline?.withEngine { $0.setPaused(paused) }
    }

    func rebuildHoldKeyTracker() {
        holdKeyTracker = HoldKeyTracker(key: settings.holdKey, mode: settings.holdKeyMode)
        let satisfied = holdKeyTracker.isSatisfied
        pipeline?.withEngine { $0.setHoldKeySatisfied(satisfied) }
    }

    /// Runs once: registers the login item, shows the welcome window and records that it was shown, so later
    /// launches skip both.
    private func firstRun() {
        if settings.launchAtLogin {
            setLaunchAtLogin(true)
        }
        showWelcome()
        var updated = settings
        updated.welcomeShown = true
        apply(updated)
    }

    /// Makes the stored Launch at Login value match the system's login item, which the user can change in System
    /// Settings. Only the stored value changes: registering or unregistering here could undo a pending approval.
    private func syncLaunchAtLogin() {
        let enabled = LaunchAtLogin.isEnabled
        guard settings.launchAtLogin != enabled else { return }
        settings.launchAtLogin = enabled
        store.save(settings)
        statusMenu?.refresh()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
        } catch {
            appLogger.error("launch at login change failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// The dispatcher with the system ports, set up from the current settings.
    private func makeDispatcher(haptics: any HapticPerforming, backlight: KeyboardBacklight?) -> CommandDispatcher {
        let externalBrightness = ExternalBrightness()
        externalBrightnessAvailable = externalBrightness != nil
        appLogger.info("external brightness available: \(externalBrightness != nil, privacy: .public)")
        let dispatcher = CommandDispatcher(
            mediaKeys: SystemMediaKeys(),
            keys: SystemKeys(),
            mouse: SystemMouse(),
            haptics: haptics,
            freezer: freezer,
            backlight: backlight,
            overlay: overlay,
            externalBrightness: externalBrightness,
            displayLocator: { DisplayLocator.displayUnderPointer() },
            volumeLevel: OutputVolumeReader(),
            brightnessLevel: BuiltInBrightnessReader(),
            missionControl: SystemMissionControl()
        )
        dispatcher.hapticStrength = settings.hapticStrength
        dispatcher.externalBrightnessEnabled = settings.externalMonitorBrightness
        dispatcher.ownAppFrontmost = FrontmostObserver.isOwnAppFrontmost
        return dispatcher
    }
}
