import Foundation

/// How a manual check ended when there is nothing to update: the menu row and General's update line show it. A found
/// release is not an outcome here, since it shows as the update row instead.
public enum UpdateCheckOutcome: Equatable, Sendable {
    case upToDate
    /// `message` says why, in the words of `UpdateCheckResult.failed`.
    case checkFailed(message: String)

    /// The outcome as one short line for General's update line: "trrek is up to date", or why the check failed.
    public var note: String {
        switch self {
        case .upToDate: String(localized: "trrek is up to date", bundle: .main)
        case let .checkFailed(message): message
        }
    }
}

/// The update row of the menu, between About trrek and Quit trrek: one row that checks, shows the outcome and then
/// runs the update in place, so the menu stays open throughout.
///
/// `idle` → (click) `checking` → `upToDate`, `checkFailed` or `update`. A known update (found by this check or an
/// automatic one) shows as `update`, whose click starts the update and whose states follow `UpdateRowState`. An
/// automatic check never shows `checking` or its outcome; a click while one runs joins it (the caller waits for that
/// check) and shows its outcome. The outcome of a manual check lasts until the menu that showed it closes.
public struct MenuUpdateRowState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case checking
        case upToDate
        /// `reason` is why the check failed, in the row's tooltip and accessibility label.
        case checkFailed(reason: String)
        case update(UpdateRowState)
    }

    /// What the row draws before its title.
    public enum Icon: Equatable, Sendable {
        case none
        case spinner
        case checkmark
        case warning
        case update
    }

    /// What a click asks the caller to do.
    public enum Click: Equatable, Sendable {
        case nothing
        case check
        case update
    }

    public private(set) var phase: Phase

    public init(update: UpdateRowState? = nil) {
        phase = update.map(Phase.update) ?? .idle
    }

    /// The row's text.
    public var title: String {
        switch phase {
        case .idle: String(localized: "Check for Updates", bundle: .main)
        case .checking: String(localized: "Checking for Updates…", bundle: .main)
        case .upToDate: String(localized: "trrek Is Up to Date", bundle: .main)
        case .checkFailed: String(localized: "Couldn’t Check — Try Again", bundle: .main)
        case let .update(row): row.title
        }
    }

    /// Why the check or the update failed: the row's tooltip, and read out after its title.
    public var failureReason: String? {
        switch phase {
        case let .checkFailed(reason): reason.isEmpty ? nil : reason
        case let .update(row): row.failureReason
        case .idle, .checking, .upToDate: nil
        }
    }

    public var accessibilityLabel: String {
        failureReason.map { "\(title). \($0)" } ?? title
    }

    /// Whether a click (or Return on the highlighted row) does something. Not while this row checks, or a download or
    /// install runs; the outcome "up to date" is a statement, not a command.
    public var isClickable: Bool {
        switch phase {
        case .idle, .checkFailed: true
        case .checking, .upToDate: false
        case let .update(row): row.isClickable
        }
    }

    public var icon: Icon {
        switch phase {
        case .idle: .none
        case .checking: .spinner
        case .upToDate: .checkmark
        case .checkFailed: .warning
        case .update: .update
        }
    }

    /// The update states stand out (semibold, accent icon); the others look like ordinary menu items.
    public var isProminent: Bool {
        if case .update = phase {
            return true
        }
        return false
    }

    /// Whether the progress bar shows after the title (while downloading and installing).
    public var showsProgressBar: Bool {
        switch phase {
        case .update(.downloading), .update(.installing): true
        case .idle, .checking, .upToDate, .checkFailed, .update: false
        }
    }

    /// The fraction downloaded; `nil` while the bar is indeterminate or hidden.
    public var progress: Double? {
        if case let .update(.downloading(_, progress)) = phase {
            return progress
        }
        return nil
    }

    /// What VoiceOver announces when the row changes from `old` to this state: the outcome of a manual check (up to
    /// date, why it failed, or the update it found), since the row changes in place without an alert.
    public func announcement(after old: MenuUpdateRowState) -> String? {
        guard case .checking = old.phase else { return nil }
        switch phase {
        case .upToDate, .checkFailed, .update(.available): return accessibilityLabel
        case .idle, .checking, .update: return nil
        }
    }

    // MARK: - Transitions

    /// A click: from `idle` or `checkFailed` this row starts checking; on an update the caller starts (or continues)
    /// it. Does nothing while the row is not clickable.
    public mutating func click() -> Click {
        guard isClickable else { return .nothing }
        switch phase {
        case .idle, .checkFailed:
            phase = .checking
            return .check
        case .update:
            return .update
        case .checking, .upToDate:
            return .nothing
        }
    }

    /// The update controller's state changed (a check started or ended, the update moved on): a known update takes
    /// the row over at once, whoever checked. A check this row started keeps `checking` until `finishCheck`.
    public mutating func show(update: UpdateRowState?) {
        if let update {
            phase = .update(update)
        } else if case .update = phase {
            phase = .idle
        }
    }

    /// The check this row started ended with `outcome` (`nil` when it found a release or did not run); `update` is
    /// the update row known now.
    public mutating func finishCheck(_ outcome: UpdateCheckOutcome?, update: UpdateRowState?) {
        if let update {
            phase = .update(update)
            return
        }
        guard case .checking = phase else { return }
        phase = switch outcome {
        case .upToDate: .upToDate
        case let .checkFailed(message): .checkFailed(reason: message)
        case nil: .idle
        }
    }

    /// The menu closed: the outcome it showed is cleared for the next time it opens. A check still running keeps
    /// `checking`; its outcome then shows the next time the menu opens.
    public mutating func menuClosed() {
        switch phase {
        case .upToDate, .checkFailed: phase = .idle
        case .idle, .checking, .update: break
        }
    }

    // MARK: - Width

    /// A version as wide as any release is likely to be, so the row fits an update found while the menu is open.
    public static let widestVersion = SemanticVersion(major: 88, minor: 88, patch: 88)

    /// Every state the row can show while the menu is open, with each of `known` (the version the row shows and the
    /// known update) and `widestVersion`; the row is as wide as the widest of them, so it never changes its width in
    /// place.
    public static func widthSamples(known: [SemanticVersion]) -> [MenuUpdateRowState] {
        var phases: [Phase] = [.idle, .checking, .upToDate, .checkFailed(reason: "")]
        for version in Set(known + [widestVersion]).sorted() {
            let updates: [UpdateRowState] = [
                .available(version), .downloading(version, progress: nil), .installing(version), .failed(version),
                .browser(version), .relaunch(version)
            ]
            phases += updates.map(Phase.update)
        }
        return phases.map { phase in
            var state = MenuUpdateRowState()
            state.phase = phase
            return state
        }
    }
}
