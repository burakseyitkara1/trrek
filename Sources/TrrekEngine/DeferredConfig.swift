/// A configuration change that must not interrupt a gesture: it is applied at once while no gesture is in
/// progress, and otherwise held until the engine is free again.
///
/// A gesture is in progress while a finger is a candidate on an edge or a slide is active (`sliding` or `lost`). In
/// `idle`, `spent` and `threeFinger` no slide can be running, so a new configuration applies at once. A pure value
/// type: the engine keeps one and asks it what to do; nothing here allocates.
public struct DeferredConfig: Sendable, Equatable {
    /// The configuration waiting for the gesture in progress to end; `nil` when none is waiting.
    public private(set) var pending: EngineConfig?

    public init() {}

    /// Whether a gesture in `kind` must not see its configuration change.
    public static func isBusy(_ kind: StateKind) -> Bool {
        switch kind {
        case .candidate, .sliding, .lost: true
        case .idle, .spent, .threeFinger: false
        }
    }

    /// Asks for `config` to be used. Returns the configuration to apply now, or `nil` when nothing changes now:
    /// `config` is the one in use (any waiting one is dropped, so the engine stays on it), or a gesture is in
    /// progress (`config` waits, replacing any earlier one).
    public mutating func request(_ config: EngineConfig, current: EngineConfig, busy: Bool) -> EngineConfig? {
        guard config != current else {
            pending = nil
            return nil
        }
        guard busy else {
            pending = nil
            return config
        }
        pending = config
        return nil
    }

    /// Called after the engine's state may have changed. Returns the waiting configuration once no gesture is in
    /// progress, and forgets it; otherwise `nil`.
    public mutating func settle(busy: Bool) -> EngineConfig? {
        guard !busy, let config = pending else { return nil }
        pending = nil
        return config
    }

    /// Drops the waiting configuration, for example because a newer one was applied directly.
    public mutating func cancel() {
        pending = nil
    }
}
