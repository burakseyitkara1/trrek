import Foundation

/// The update row at the top of the menu (and its line in General): what it says and whether a click does something.
///
/// `available` → (click) `downloading` → `installing` → trrek relaunches. A failed download, verification or install
/// ends in `failed`, whose click starts again; when trrek cannot replace itself it opens the release page and ends in
/// `browser`, whose click opens the page again. `relaunch` is an installed update whose relaunch did not start.
public enum UpdateRowState: Equatable, Sendable {
    case available(SemanticVersion)
    /// `progress` is the fraction received, `nil` while the size is unknown.
    case downloading(SemanticVersion, progress: Double?)
    case installing(SemanticVersion)
    case failed(SemanticVersion)
    case browser(SemanticVersion)
    case relaunch(SemanticVersion)

    public var version: SemanticVersion {
        switch self {
        case let .available(version), let .downloading(version, _), let .installing(version), let .failed(version),
             let .browser(version), let .relaunch(version):
            version
        }
    }

    /// A download or an install runs; checks wait and clicks do nothing.
    public var isBusy: Bool {
        switch self {
        case .downloading, .installing: true
        case .available, .failed, .browser, .relaunch: false
        }
    }

    /// The update is installed and waits for trrek to relaunch.
    public var isAwaitingRelaunch: Bool {
        if case .relaunch = self {
            return true
        }
        return false
    }

    /// A click starts (or restarts) the update, opens the release page or relaunches.
    public var isClickable: Bool {
        !isBusy
    }

    /// The menu row's text.
    public var title: String {
        let version = version.description
        return switch self {
        case .available: String(localized: "Update Available: trrek \(version)", bundle: .main)
        case .downloading: String(localized: "Downloading trrek \(version)…", bundle: .main)
        case .installing: String(localized: "Installing trrek \(version)…", bundle: .main)
        case .failed: String(localized: "Update Failed — Try Again", bundle: .main)
        case .browser: String(localized: "Update in Browser…", bundle: .main)
        case .relaunch: String(localized: "Relaunch to Finish Updating", bundle: .main)
        }
    }

    /// The line in General.
    public var statusText: String {
        let version = version.description
        return switch self {
        case .available, .browser: String(localized: "trrek \(version) is available", bundle: .main)
        case .downloading, .installing: title
        case .failed: String(localized: "The update failed.", bundle: .main)
        case .relaunch: String(localized: "trrek \(version) is installed", bundle: .main)
        }
    }

    /// The button next to the line in General; `nil` while busy.
    public var actionTitle: String? {
        switch self {
        case .available: String(localized: "Update Now", bundle: .main)
        case .failed: String(localized: "Try Again", bundle: .main)
        case .browser: String(localized: "Update in Browser…", bundle: .main)
        case .relaunch: String(localized: "Relaunch", bundle: .main)
        case .downloading, .installing: nil
        }
    }

    // MARK: - Transitions

    /// A click: `available` and `failed` start downloading; anything else stays (the caller handles `browser` and
    /// `relaunch`). Returns whether a download starts.
    public mutating func start() -> Bool {
        switch self {
        case let .available(version), let .failed(version):
            self = .downloading(version, progress: nil)
            return true
        case .downloading, .installing, .browser, .relaunch:
            return false
        }
    }

    /// Download progress. Returns whether the shown value changed (by at least a whole percent), so the row redraws
    /// at most a hundred times per download.
    @discardableResult
    public mutating func progress(received: Int64, expected: Int64) -> Bool {
        guard case let .downloading(version, old) = self else { return false }
        let fraction: Double? = expected > 0 ? min(max(Double(received) / Double(expected), 0), 1) : nil
        let changed = switch (old, fraction) {
        case let (old?, new?): (old * 100).rounded(.down) != (new * 100).rounded(.down)
        case (nil, nil): false
        default: true
        }
        if changed {
            self = .downloading(version, progress: fraction)
        }
        return changed
    }

    /// The download finished; mounting, verifying and replacing follow.
    public mutating func downloaded() {
        if case let .downloading(version, _) = self {
            self = .installing(version)
        }
    }

    public mutating func fail() {
        self = .failed(version)
    }

    public mutating func fallBackToBrowser() {
        self = .browser(version)
    }

    public mutating func installedWithoutRelaunch() {
        self = .relaunch(version)
    }
}
