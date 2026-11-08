/// Why the trackpad is not feeding gestures.
public enum TrackpadIssue: Sendable, Equatable {
    /// No trackpad was found, or none could be started.
    case notFound
    /// A trackpad's first frame was out of range; the pipeline stopped itself.
    case dataUnavailable
}

/// The status line at the top of the menu bar menu.
public enum StatusText {
    /// The first state that applies, in priority order: a trackpad issue, missing Accessibility access, a paused app
    /// (`pausedAppName` is the name of the app trrek is paused in, or `nil`), and otherwise active.
    public static func text(
        trackpadIssue: TrackpadIssue?,
        accessibilityTrusted: Bool,
        pausedAppName: String?
    ) -> String {
        switch trackpadIssue {
        case .notFound: return String(localized: "Trackpad not found", bundle: .main)
        case .dataUnavailable: return String(localized: "Trackpad data unavailable", bundle: .main)
        case nil: break
        }
        if !accessibilityTrusted {
            return String(localized: "Accessibility access needed", bundle: .main)
        }
        if let pausedAppName {
            return String(localized: "Paused in \(pausedAppName)", bundle: .main)
        }
        return String(localized: "trrek is active", bundle: .main)
    }

    /// The line under the status line while the app in front runs edges of its own: "Edges set for <app>". `nil`
    /// while trrek is not active (`isActive` is false for a trackpad issue or missing Accessibility, when the status
    /// line says so instead), when the app (`bundleID`) is paused (pausing wins over its edges), or when its edges are
    /// the All Apps ones (no profile, or one that sets nothing different).
    public static func edgeProfileLine(
        bundleID: String?,
        appName: String,
        settings: Settings,
        isActive: Bool
    ) -> String? {
        guard isActive, let bundleID, !settings.pausedBundleIDs.contains(bundleID),
              settings.edgeActions(for: bundleID) != settings.edgeActions(for: nil)
        else { return nil }
        return String(localized: "Edges set for \(appName)", bundle: .main)
    }
}

/// Which application's pause state applies to the engine.
///
/// Normally the frontmost application's. While trrek itself is frontmost (its settings, welcome or About window) the
/// application that was in front before it keeps deciding, so opening a trrek window over a paused app does not
/// un-pause the edges, and opening one over an active app does not pause them.
public struct FrontmostPause: Sendable, Equatable {
    /// The bundle ID of the latest frontmost application other than trrek; `nil` when it had none, or before any.
    public private(set) var bundleID: String?

    public init(bundleID: String? = nil) {
        self.bundleID = bundleID
    }

    /// Records an application that became frontmost. trrek's own activation changes nothing.
    public mutating func activated(bundleID: String?, isOwnApp: Bool) {
        guard !isOwnApp else { return }
        self.bundleID = bundleID
    }

    /// Whether the engine is paused, given the paused applications' bundle IDs.
    public func isPaused(in pausedBundleIDs: [String]) -> Bool {
        bundleID.map(pausedBundleIDs.contains) ?? false
    }
}
