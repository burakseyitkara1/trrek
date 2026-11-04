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

    private static let accessibilityPaneURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")

    let windows = WindowRegistry()
    private lazy var settingsWindowController = SettingsWindowController(registry: windows)
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

    func start() {
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
        let dispatcher = CommandDispatcher(
            mediaKeys: SystemMediaKeys(),
            keys: SystemKeys(),
            mouse: SystemMouse(),
            haptics: haptics,
            freezer: freezer,
            backlight: backlight,
            overlay: nil
        )
        dispatcher.hapticStrength = settings.hapticStrength
        let config = engineConfig()
        let engine = GestureEngine(config: config, sink: dispatcher)
        self.dispatcher = dispatcher
        pipeline = GesturePipeline(engine: engine, lostTimeout: config.thresholds.lostTimeout)

        rebuildHoldKeyTracker()
        updatePause()
        startPipeline()
        startInputMonitor()
        startObservers()
        statusMenu = StatusMenu(coordinator: self)

        if !settings.welcomeShown {
            firstRun()
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
        if previous.holdKey != newSettings.holdKey || previous.holdKeyMode != newSettings.holdKeyMode {
            rebuildHoldKeyTracker()
        }
        if previous.launchAtLogin != newSettings.launchAtLogin {
            setLaunchAtLogin(newSettings.launchAtLogin)
        }
        updatePause()
        statusMenu?.refresh()
        windows.settingsModel?.refresh(from: newSettings)
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

    func showWelcome() {
        appLogger.info("welcome window not implemented yet")
    }

    /// The first request shows the system prompt only. The system shows that prompt once per app, so a later
    /// request while still untrusted opens the Accessibility pane instead of doing nothing.
    func grantAccessibility() {
        let promptedBefore = accessibilityPrompted
        accessibilityPrompted = true
        Permissions.prompt()
        guard promptedBefore, !Permissions.isTrusted, let url = Self.accessibilityPaneURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Helpers

    /// Pauses the engine while the frontmost application is in the paused list.
    func updatePause() {
        let paused = FrontmostObserver.currentBundleID.map(settings.pausedBundleIDs.contains) ?? false
        pipeline?.withEngine { $0.setPaused(paused) }
    }

    func rebuildHoldKeyTracker() {
        holdKeyTracker = HoldKeyTracker(key: settings.holdKey, mode: settings.holdKeyMode)
        let satisfied = holdKeyTracker.isSatisfied
        pipeline?.withEngine { $0.setHoldKeySatisfied(satisfied) }
    }

    private func firstRun() {
        if settings.launchAtLogin {
            setLaunchAtLogin(true)
        }
        // Task for the welcome window: mark `welcomeShown` once it has actually been shown.
        appLogger.info("welcome pending")
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
        } catch {
            appLogger.error("launch at login change failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static func makeHaptics() -> any HapticPerforming {
        let devices = MultitouchDevices.enumerate()
        let identifier = devices.first(where: \.isBuiltIn)?.multitouchID
            ?? devices.lazy.compactMap(\.multitouchID).first
        if let identifier, let actuator = ActuatorHaptics(multitouchID: identifier) {
            return actuator
        }
        appLogger.error("trackpad actuator unavailable; using system haptics")
        return SystemHaptics()
    }
}
