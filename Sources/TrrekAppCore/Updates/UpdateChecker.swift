import Foundation
import TrrekPlatform

/// Fetches the latest release's JSON; replaced by a fake in tests.
public protocol ReleaseFeed: Sendable {
    func latestRelease() async throws -> Data
}

/// What a check found.
public enum UpdateCheckResult: Equatable, Sendable {
    /// The policy did not allow an automatic check now.
    case skipped
    /// The running version is the latest (or newer); carries the latest published version.
    case upToDate(latest: SemanticVersion)
    /// A newer release.
    case available(ReleaseInfo)
    /// The check failed; carries the explanation for the alert.
    case failed(message: String)
}

/// Checks the feed when the policy allows and remembers the outcome in `UpdateStateStore`.
@MainActor
public final class UpdateChecker {
    /// The version compared with the feed: the running one, or the one `--assume-version` names.
    public let currentVersion: SemanticVersion
    private let feed: any ReleaseFeed
    private let state: UpdateStateStore
    private let now: () -> Date
    private var checksRunning = 0
    /// Called when a check starts and when it ends, after its outcome is stored.
    public var onStateChange: (() -> Void)?

    /// A stored update that is not newer than `currentVersion` (trrek was updated since) is forgotten.
    public init(
        currentVersion: SemanticVersion,
        feed: any ReleaseFeed,
        state: UpdateStateStore,
        now: @escaping () -> Date = Date.init
    ) {
        self.currentVersion = currentVersion
        self.feed = feed
        self.state = state
        self.now = now
        if let stored = state.availableUpdate, stored.version <= currentVersion {
            state.availableUpdate = nil
        }
    }

    /// The newer release the last successful check found.
    public var availableUpdate: ReleaseInfo? {
        state.availableUpdate
    }

    /// The last successful check.
    public var lastCheck: Date? {
        state.lastCheck
    }

    public var isChecking: Bool {
        checksRunning > 0
    }

    /// Whether `trigger` would check now. Automatic checks also wait while another check runs.
    public func isDue(_ trigger: UpdateCheckTrigger, automatic: Bool) -> Bool {
        if trigger.isAutomatic, isChecking {
            return false
        }
        return UpdateCheckPolicy.shouldCheck(
            trigger: trigger,
            automatic: automatic,
            lastCheck: state.lastCheck,
            lastFailure: state.lastFailure,
            now: now()
        )
    }

    /// Checks the feed if `isDue` allows. A newer release is stored (the menu bar icon and the menu show it); anything
    /// else clears the stored one.
    public func check(_ trigger: UpdateCheckTrigger, automatic: Bool) async -> UpdateCheckResult {
        guard isDue(trigger, automatic: automatic) else { return .skipped }
        checksRunning += 1
        onStateChange?()
        defer {
            checksRunning -= 1
            onStateChange?()
        }
        let release: ReleaseInfo
        do {
            release = try await ReleaseInfo.decode(feed.latestRelease())
        } catch {
            state.lastFailure = now()
            let message = Self.message(for: error)
            appLogger.error("update check failed", error)
            return .failed(message: message)
        }
        state.lastCheck = now()
        state.lastFailure = nil
        guard release.version > currentVersion else {
            state.availableUpdate = nil
            appLogger.notice("update check: \(release.version, privacy: .public) is the latest")
            return .upToDate(latest: release.version)
        }
        state.availableUpdate = release
        appLogger.notice("update check: \(release.version, privacy: .public) is available")
        return .available(release)
    }

    /// The text shown for a failed check: the same words as General for an unavailable server or a missing network
    /// (after the feed's retries), otherwise what went wrong.
    public static func message(for error: any Error) -> String {
        let failure = UpdateFailure(error)
        if failure == .serverUnavailable || failure == .offline, let reason = failure.reason {
            return reason
        }
        if let error = error as? ReleaseFeedError {
            return error.message
        }
        return error.localizedDescription
    }
}
