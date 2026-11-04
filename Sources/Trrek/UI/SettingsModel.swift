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
    /// Whether the DDC/CI bridge exists on this Mac; without it the External Monitor Brightness toggle is disabled.
    let externalBrightnessAvailable: Bool
    var accessibilityGranted: Bool
    var selectedTab: SettingsTab = .general

    /// Whether the Reset to Defaults confirmation is showing. Window state lives here rather than in view state,
    /// so it goes away with the window.
    var confirmingReset = false
    /// The bundle ID of the selected row in the paused apps list.
    var selectedPausedApp: String?

    /// Looks up an app's name and icon; replaced in tests.
    @ObservationIgnored var appInfoResolver: (String) -> PausedAppInfo = PausedAppInfo.init(bundleID:)
    /// Each paused app's name and icon, resolved once per bundle ID while the window is open.
    @ObservationIgnored private var appInfoCache: [String: PausedAppInfo] = [:]

    @ObservationIgnored private let onChange: (AppSettings) -> Void
    @ObservationIgnored private var isRefreshing = false

    init(
        settings: AppSettings,
        backlightAvailable: Bool,
        externalBrightnessAvailable: Bool = true,
        accessibilityGranted: Bool = false,
        onChange: @escaping (AppSettings) -> Void
    ) {
        self.settings = settings
        self.backlightAvailable = backlightAvailable
        self.externalBrightnessAvailable = externalBrightnessAvailable
        self.accessibilityGranted = accessibilityGranted
        self.onChange = onChange
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

    /// Restores the defaults, keeping Launch at Login and whether the welcome window was shown.
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
