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
    enum TrackpadIssue {
        case notFound, dataUnavailable
    }

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

    let freezer = CursorFreezerSlot()
    private var backlight: KeyboardBacklight?
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

        // Haptics enumerate the devices, so they are built before the pipeline takes its own device list.
        let haptics = Self.makeHaptics()
        let backlight = KeyboardBacklight()
        self.backlight = backlight
        appLogger.info("keyboard backlight available: \(backlight != nil, privacy: .public)")
        freezer.replace(with: EventTapGuard())
        let dispatcher = makeDispatcher(haptics: haptics, backlight: backlight)
        let config = engineConfig()
        let engine = GestureEngine(config: config, sink: dispatcher)
        self.dispatcher = dispatcher
        let pipeline = GesturePipeline(engine: engine, lostTimeout: config.thresholds.lostTimeout)
        pipeline.onDataUnavailable = { [weak self] _ in
            MainActor.assumeIsolated { self?.trackpadDataUnavailable() }
        }
        self.pipeline = pipeline

        rebuildHoldKeyTracker()
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

    /// The application in front, unless it is trrek itself.
    var frontApp: NSRunningApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        return app
    }

    /// Whether the hold key works as a toggle and is currently switched on.
    var isHoldToggleActive: Bool {
        settings.holdKey != .none && settings.holdKeyMode == .toggle && holdKeyTracker.isSatisfied
    }

    var statusText: String {
        switch trackpadIssue {
        case .notFound: return "Trackpad not found"
        case .dataUnavailable: return "Trackpad data unavailable"
        case nil: break
        }
        if !isTrusted {
            return "Accessibility access needed"
        }
        if let app = frontApp, let id = app.bundleIdentifier, settings.pausedBundleIDs.contains(id) {
            return "Paused in \(app.localizedName ?? id)"
        }
        return "trrek is active"
    }

    // MARK: - Menu actions

    func pauseInFrontApp() {
        guard let id = frontApp?.bundleIdentifier, !settings.pausedBundleIDs.contains(id) else { return }
        var updated = settings
        updated.pausedBundleIDs.append(id)
        apply(updated)
    }

    func resumeInFrontApp() {
        guard let id = frontApp?.bundleIdentifier else { return }
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
            accessibilityGranted: isTrusted,
            onChange: { [weak self] in self?.apply($0) }
        )
        if let tab = SettingsTab(argument: tab) {
            model.selectedTab = tab
        }
        settingsWindowController.show(model: model)
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

    /// Pauses the engine while the frontmost application is in the paused list. `bundleID` is the frontmost
    /// application's; an activation notification passes the one it carries.
    func updatePause(bundleID: String? = FrontmostObserver.currentBundleID) {
        let paused = bundleID.map(settings.pausedBundleIDs.contains) ?? false
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
        let dispatcher = CommandDispatcher(
            mediaKeys: SystemMediaKeys(),
            keys: SystemKeys(),
            mouse: SystemMouse(),
            haptics: haptics,
            freezer: freezer,
            backlight: backlight,
            overlay: overlay,
            externalBrightness: ExternalBrightness(),
            displayLocator: { DisplayLocator.displayUnderPointer() }
        )
        dispatcher.hapticStrength = settings.hapticStrength
        dispatcher.externalBrightnessEnabled = settings.externalMonitorBrightness
        return dispatcher
    }

    private static func makeHaptics() -> any HapticPerforming {
        // The actuator of a device that never drives gestures would answer for the wrong surface.
        let devices = MultitouchDevices.enumerate().filter { $0.kind != .other }
        let identifier = devices.first(where: \.isBuiltIn)?.multitouchID
            ?? devices.lazy.compactMap(\.multitouchID).first
        if let identifier, let actuator = ActuatorHaptics(multitouchID: identifier) {
            return actuator
        }
        appLogger.error("trackpad actuator unavailable; using system haptics")
        return SystemHaptics()
    }
}
