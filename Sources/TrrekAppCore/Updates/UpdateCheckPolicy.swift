import Foundation

/// What started an update check.
public enum UpdateCheckTrigger: String, Sendable {
    /// Shortly after launch.
    case launch
    /// The menu bar menu opened.
    case menuOpened
    /// Shortly after the Mac woke.
    case wake
    /// Check for Updates in the menu, or Check Now in General.
    case manual

    public var isAutomatic: Bool {
        self != .manual
    }
}

/// When to check. There is no timer: checks happen at launch, wake and menu opening, and only
/// when this allows.
public enum UpdateCheckPolicy {
    /// Automatic checks run at most this often after a successful one.
    public static let interval: TimeInterval = 24 * 60 * 60
    /// After a failed check (offline, server error) the next automatic one waits this long.
    public static let retryInterval: TimeInterval = 60 * 60

    /// Whether to check now. A manual check always runs. An automatic one runs when automatic checks are on, the
    /// last successful check is `interval` old (or there was none) and the last failure is `retryInterval` old (or
    /// there was none). A date in the future (the clock was set back) counts as old.
    public static func shouldCheck(
        trigger: UpdateCheckTrigger,
        automatic: Bool,
        lastCheck: Date?,
        lastFailure: Date?,
        now: Date
    ) -> Bool {
        guard trigger.isAutomatic else { return true }
        guard automatic else { return false }
        return isOld(lastCheck, interval, now) && isOld(lastFailure, retryInterval, now)
    }

    private static func isOld(_ date: Date?, _ age: TimeInterval, _ now: Date) -> Bool {
        guard let date else { return true }
        return date > now || now.timeIntervalSince(date) >= age
    }
}
