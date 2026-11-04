import CoreGraphics
import Foundation
import TrrekPlatform

/// An external brightness port with a fixed set of external displays. Steps move by 1/16 (1/64 when fine),
/// after an optional delay; `failing` makes every step fail. The dispatcher calls `step` on its display queue, so
/// the recorded state is locked.
final class FakeExternalBrightness: ExternalBrightnessControlling, @unchecked Sendable {
    struct Step: Equatable {
        let display: CGDirectDisplayID
        let direction: Int
        let fine: Bool
    }

    private let lock = NSLock()
    private let externals: Set<CGDirectDisplayID>
    private let delay: TimeInterval
    private let failing: Bool
    private var level: Float
    private var recorded: [Step] = []
    private var stepQueues: [Bool] = []
    /// Set on the queue the steps are expected to run on.
    let queueKey = DispatchSpecificKey<Bool>()

    init(externals: Set<CGDirectDisplayID>, level: Float = 0.5, delay: TimeInterval = 0, failing: Bool = false) {
        self.externals = externals
        self.level = level
        self.delay = delay
        self.failing = failing
    }

    var steps: [Step] {
        lock.withLock { recorded }
    }

    /// For each step, whether it ran on a queue marked with `queueKey`.
    var stepsOnMarkedQueue: [Bool] {
        lock.withLock { stepQueues }
    }

    func isExternal(display: CGDirectDisplayID) -> Bool {
        externals.contains(display)
    }

    func step(display: CGDirectDisplayID, direction: Int, fine: Bool) -> Float? {
        if delay > 0 {
            Thread.sleep(forTimeInterval: delay)
        }
        return lock.withLock {
            recorded.append(Step(display: display, direction: direction, fine: fine))
            stepQueues.append(DispatchQueue.getSpecific(key: queueKey) == true)
            guard !failing else { return nil }
            level = min(1, max(0, level + Float(direction) * (fine ? 1 / 64 : 1 / 16)))
            return level
        }
    }
}

/// A display locator that returns whatever display the test puts under the pointer.
final class FakeDisplayLocator: @unchecked Sendable {
    private let lock = NSLock()
    private var current: CGDirectDisplayID?

    init(_ display: CGDirectDisplayID?) {
        current = display
    }

    var display: CGDirectDisplayID? {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }

    func locate() -> CGDirectDisplayID? {
        display
    }
}
