import Foundation

/// The gates of spec 5.6: the palm filter, the typing gate, Hold-to-Slide and pause, with the host signals
/// that drive them. Like the rest of the engine, nothing here allocates on the heap.
extension GestureEngine {
    /// The touch-down time given to fingers that a gate kept from starting a gesture. Seen from any frame,
    /// the three-finger settle window has long passed, so these fingers cannot arm a middle click before
    /// they all lift.
    static let blockedDownTime: TimeInterval = -.infinity

    /// Records a key press; for `typingGate` seconds after it no new gesture starts. An active slide or
    /// middle click is not affected.
    public func noteKeyDown(at time: TimeInterval) {
        lastKeyDown = time
    }

    /// Reports whether the Hold-to-Slide key is down. When the key is required and released, an active slide
    /// is committed and any other gesture in progress is dropped without commands.
    public func setHoldKeySatisfied(_ satisfied: Bool) {
        holdKeySatisfied = satisfied
        guard config.holdKeyRequired, !satisfied else { return }
        switch state {
        case let .sliding(data), let .lost(data, _):
            finish(data, .commit)
            state = .idle
        case let .candidate(data):
            var start = TouchBuffer()
            start.append(Touch(id: data.touchID, x: data.x0, y: data.y0, majorAxisMM: 0))
            state = .spent(firstDownTime: Self.blockedDownTime, start: start)
        case let .threeFinger(_, start, _):
            state = .spent(firstDownTime: Self.blockedDownTime, start: start)
        case .idle, .spent:
            break
        }
    }

    /// Pauses or resumes the engine. Pausing commits an active slide and drops any other gesture without
    /// commands; while paused, every frame is ignored.
    public func setPaused(_ paused: Bool) {
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
