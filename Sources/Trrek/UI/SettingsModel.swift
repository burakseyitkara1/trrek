import AppKit
import Observation
import TrrekAppCore

/// The app's settings model; spelled out because SwiftUI has a `Settings` scene type of its own.
typealias AppSettings = TrrekAppCore.Settings

/// What the settings window shows and edits. Exists only while the window is open.
///
/// Every change the window makes to `settings` is passed to `onChange`, which stores and applies it.
@MainActor
@Observable
final class SettingsModel {
    var settings: AppSettings {
        didSet {
            guard settings != oldValue, !isRefreshing else { return }
            onChange(settings)
        }
    }

    let backlightAvailable: Bool
    /// The localization this launch shows (`"en"`, `"tr"`); when the chosen language resolves to another one, the
    /// General tab offers to relaunch.
    let launchLocalization: String
    /// The localization a language setting resolves to on this Mac.
    @ObservationIgnored let localization: (AppLanguage) -> String
    /// Whether the app can reopen itself (it runs from an app bundle).
    let canRelaunch: Bool
    /// Whether the DDC/CI bridge exists on this Mac; without it the External Monitor Brightness toggle is disabled.
    let externalBrightnessAvailable: Bool
    var accessibilityGranted: Bool
    var selectedTab: SettingsTab = .general

    /// Whether the Reset to Defaults confirmation is showing. Window state lives here rather than in view state,
    /// so it goes away with the window.
    var confirmingReset = false
    /// The bundle ID of the selected row in the paused apps list.
    var selectedPausedApp: String?
    /// Settings read from a `.trrek` file for the import confirmation. Kept after the alert closes, so its title
    /// does not change while it animates out; the next import replaces it.
    var pendingImport: PendingImport?
    var isConfirmingImport = false
    /// The last import or export failure, kept after its alert closes for the same reason.
    var transferFailure: TransferFailure?
    var isShowingTransferFailure = false
    /// Whether a settings file is being read.
    var isReadingImport = false
    /// The last successful update check, shown under Check Now.
    var lastUpdateCheck: Date?
    /// Whether an update check is running.
    var isCheckingForUpdates = false
    /// Whether an update check or download is running; Check Now is disabled meanwhile.
    var isUpdateBusy = false

    /// Looks up an app's name and icon; replaced in tests.
    @ObservationIgnored var appInfoResolver: (String) -> PausedAppInfo = PausedAppInfo.init(bundleID:)
    /// Each paused app's name and icon, resolved once per bundle ID while the window is open.
    @ObservationIgnored private var appInfoCache: [String: PausedAppInfo] = [:]

    /// The settings window, set by its controller; sheets such as the paused apps open panel attach to it.
    @ObservationIgnored weak var window: NSWindow?

    @ObservationIgnored private let onChange: (AppSettings) -> Void
    /// Quits and reopens the app.
    @ObservationIgnored let relaunch: () -> Void
    /// Runs a manual update check whose alert attaches to the given window.
    @ObservationIgnored private let checkForUpdates: (NSWindow?) -> Void
    @ObservationIgnored private var isRefreshing = false

    init(
        settings: AppSettings,
        backlightAvailable: Bool,
        externalBrightnessAvailable: Bool = true,
        accessibilityGranted: Bool = false,
        launchLocalization: String = "en",
        localization: @escaping (AppLanguage) -> String = { $0 == .turkish ? "tr" : "en" },
        canRelaunch: Bool = false,
        relaunch: @escaping () -> Void = {},
        lastUpdateCheck: Date? = nil,
        isCheckingForUpdates: Bool = false,
        checkForUpdates: @escaping (NSWindow?) -> Void = { _ in },
        onChange: @escaping (AppSettings) -> Void
    ) {
        self.settings = settings
        self.backlightAvailable = backlightAvailable
        self.launchLocalization = launchLocalization
        self.localization = localization
        self.canRelaunch = canRelaunch
        self.relaunch = relaunch
        self.lastUpdateCheck = lastUpdateCheck
        self.isCheckingForUpdates = isCheckingForUpdates
        self.checkForUpdates = checkForUpdates
        self.externalBrightnessAvailable = externalBrightnessAvailable
        self.accessibilityGranted = accessibilityGranted
        self.onChange = onChange
    }

    /// Whether the chosen language shows a different localization from the one this launch uses, so it takes effect
    /// only after a relaunch. Choosing Türkçe while System already shows Turkish needs none.
    var needsRelaunch: Bool {
        localization(settings.language) != launchLocalization
    }

    /// Shows settings changed elsewhere (the menu bar menu) without passing them back to `onChange`.
    func refresh(from settings: AppSettings) {
        isRefreshing = true
        self.settings = settings
        isRefreshing = false
    }

    /// The name and icon of the app with `bundleID`, looked up on first use and cached for the window's lifetime.
    func appInfo(for bundleID: String) -> PausedAppInfo {
        if let cached = appInfoCache[bundleID] {
            return cached
        }
        let info = appInfoResolver(bundleID)
        appInfoCache[bundleID] = info
        return info
    }

    /// Adds the apps at `urls` to the paused list, skipping anything without a bundle ID.
    func addPausedApps(at urls: [URL]) {
        addPausedApps(bundleIDs: urls.compactMap { Bundle(url: $0)?.bundleIdentifier })
    }

    /// Adds `bundleIDs` to the paused list in order, skipping ones already listed and trrek itself (pausing in trrek
    /// would pause the edges whenever its own windows are in front).
    func addPausedApps(bundleIDs: [String]) {
        var updated = settings.pausedBundleIDs
        for id in bundleIDs where id != AppIdentity.bundleID && !updated.contains(id) {
            updated.append(id)
        }
        settings.pausedBundleIDs = updated
    }

    /// Check Now: checks for updates, with the outcome shown as a sheet on the settings window.
    func checkForUpdatesNow() {
        checkForUpdates(window)
    }

    /// The line under Check Now.
    var updateCheckStatus: String {
        if isCheckingForUpdates {
            return String(localized: "Checking…", bundle: .main)
        }
        guard let lastUpdateCheck else {
            return String(localized: "Not checked yet", bundle: .main)
        }
        let date = lastUpdateCheck.formatted(date: .abbreviated, time: .shortened)
        return String(localized: "Last checked: \(date)", bundle: .main)
    }

    /// Restores the defaults, keeping Launch at Login, the language and whether the welcome window was shown.
    func resetToDefaults() {
        settings = settings.resetToDefaults(backlightAvailable: backlightAvailable)
    }
}

/// The name and icon of an installed app; falls back to the bundle ID and a generic icon when it is not found.
struct PausedAppInfo {
    let name: String
    let icon: NSImage

    init(name: String, icon: NSImage) {
        self.name = name
        self.icon = icon
    }

    init(bundleID: String) {
        let workspace = NSWorkspace.shared
        guard let url = workspace.urlForApplication(withBundleIdentifier: bundleID) else {
            self.init(name: bundleID, icon: workspace.icon(for: .applicationBundle))
            return
        }
        let displayName = FileManager.default.displayName(atPath: url.path)
        let name = displayName.hasSuffix(".app") ? String(displayName.dropLast(4)) : displayName
        self.init(name: name, icon: workspace.icon(forFile: url.path))
    }
}
