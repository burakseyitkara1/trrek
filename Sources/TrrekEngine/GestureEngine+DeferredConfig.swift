/// Configuration changes that wait for the gesture in progress (`DeferredConfig`), used when the edges follow the app
/// in front. The waiting configuration is settled at the end of every locked body that can end a gesture, and before
/// a new gesture starts.
public extension GestureEngine {
    /// Applies a new configuration without disturbing the gesture in progress: at once while no finger is a
    /// candidate and no slide is active, otherwise as soon as that gesture ends (before the next one can start).
    /// The slide in progress keeps its action and configuration to the end. A later call replaces a configuration
    /// that is still waiting; asking for the configuration in use does nothing and drops a waiting one.
    func updateWhenIdle(config: EngineConfig) {
        lock.withLock {
            let busy = DeferredConfig.isBusy(stateKindLocked)
            if let now = deferredConfig.request(config, current: self.config, busy: busy) {
                updateLocked(config: now)
            }
        }
    }
}

extension GestureEngine {
    /// Applies the configuration waiting from `updateWhenIdle(config:)` once no gesture is in progress. Costs one
    /// check of an optional when nothing waits, so it runs after every frame.
    func settleDeferredConfigLocked() {
        guard deferredConfig.pending != nil,
              let config = deferredConfig.settle(busy: DeferredConfig.isBusy(stateKindLocked))
        else { return }
        updateLocked(config: config)
    }
}
