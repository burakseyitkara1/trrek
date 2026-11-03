import Synchronization
import TrrekPlatform

/// Forwards cursor freezing to the current `EventTapGuard`. A guard can only create its tap when it is
/// initialized, so a new one is put in place once Accessibility is granted. Safe from any thread.
final class CursorFreezerSlot: CursorFreezing, Sendable {
    private let current = Mutex<EventTapGuard?>(nil)

    /// Installs `newGuard`; the previous guard is unfrozen and released.
    func replace(with newGuard: EventTapGuard) {
        let previous = current.withLock { slot in
            let previous = slot
            slot = newGuard
            return previous
        }
        previous?.setFreeze(false)
    }

    func setFreeze(_ on: Bool) {
        current.withLock { $0?.setFreeze(on) }
    }
}
