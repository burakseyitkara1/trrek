import Foundation

/// The gates of spec 5.6: the palm filter, the typing gate, Hold-to-Slide and pause, with the host signals
/// that drive them. The public entry points live in `GestureEngine.swift` and call the `*Locked` bodies here
/// with the engine's lock held. Like the rest of the engine, nothing here allocates on the heap.
extension GestureEngine {
    /// The touch-down time given to fingers that a gate kept from starting a gesture. Seen from any frame,
    /// the three-finger settle window has long passed, so these fingers cannot arm a middle click before
    /// they all lift.
    static let blockedDownTime: TimeInterval = -.infinity

    /// Body of `setHoldKeySatisfied(_:)`; the caller holds the lock.
    func setHoldKeySatisfiedLocked(_ satisfied: Bool) {
        defer { settleDeferredConfigLocked() }
        holdKeySatisfied = satisfied
        guard config.holdKeyRequired, !satisfied else { return }
        switch state {
        case let .sliding(data), let .lost(data, _):
            finish(data, .commit)
            state = .idle
        case let .candidate(data):
            var start = TouchBuffer()
            start.append(data.origin)
            enterSpent(firstDownTime: Self.blockedDownTime, start: start)
        case let .threeFinger(_, start, _):
            enterSpent(firstDownTime: Self.blockedDownTime, start: start)
        case .idle, .spent:
            break
        }
    }

    /// Body of `setPaused(_:)`; the caller holds the lock.
    func setPausedLocked(_ paused: Bool) {
        defer { settleDeferredConfigLocked() }
        self.paused = paused
        guard paused else { return }
        switch state {
        case let .sliding(data), let .lost(data, _):
            finish(data, .commit)
        default:
            break
        }
        state = .idle
        lastTap = nil
    }

    /// Whether a new gesture (a candidate, a slide, a tap or a middle click) may begin at `time`: not within
    /// `typingGate` of the last key press, and not while a required hold key is up.
    func admitsNewGesture(at time: TimeInterval) -> Bool {
        if time - lastKeyDown < config.thresholds.typingGate {
            return false
        }
        if config.holdKeyRequired, !holdKeySatisfied {
            return false
        }
        return true
    }

    /// The frame without touches larger than `maxMajorAxisMM` (palms). Built on the stack.
    static func withoutPalms(_ frame: Frame, maxMajorAxisMM: Float) -> Frame {
        var filtered = frame
        var touches = TouchBuffer()
        for index in 0 ..< frame.touches.count where frame.touches[index].majorAxisMM <= maxMajorAxisMM {
            touches.append(frame.touches[index])
        }
        filtered.touches = touches
        return filtered
    }
}
