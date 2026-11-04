import Dispatch
import Synchronization
import Testing
@testable import TrrekPlatform

/// A brightness client: counts reads and records writes, which arrive on the bridge's write queue.
private final class FakeClient: Sendable {
    private struct State {
        var level: Float
        var reads = 0
        var writes: [Float] = []
        var failWrites = false
    }

    private let state: Mutex<State>

    init(level: Float) {
        state = Mutex(State(level: level))
    }

    var reads: Int {
        state.withLock { $0.reads }
    }

    var writes: [Float] {
        state.withLock { $0.writes }
    }

    func setFailing(_ failing: Bool) {
        state.withLock { $0.failWrites = failing }
    }

    func read() -> Float {
        state.withLock {
            $0.reads += 1
            return $0.level
        }
    }

    func write(_ level: Float) -> Bool {
        state.withLock {
            $0.writes.append(level)
            guard !$0.failWrites else { return false }
            $0.level = level
            return true
        }
    }
}

private func makeBacklight(_ client: FakeClient, queue: DispatchQueue) -> KeyboardBacklight {
    KeyboardBacklight(read: client.read, write: client.write, queue: queue)
}

@Test func stepsWhileAWriteIsQueuedCoalesceToTheNewestTarget() {
    let client = FakeClient(level: 0.5)
    let queue = DispatchQueue(label: "test.backlight.coalesce")
    let backlight = makeBacklight(client, queue: queue)
    // Hold the queue so the steps pile up behind the first queued write.
    queue.suspend()
    #expect(backlight.step(1, fine: false) == 0.5625)
    #expect(backlight.step(1, fine: false) == 0.625)
    #expect(backlight.step(1, fine: false) == 0.6875)
    queue.resume()
    queue.sync {}
    #expect(client.writes == [0.6875])
    // One read at the start; the rest came from the cache.
    #expect(client.reads == 1)
    #expect(backlight.level() == 0.6875)
    #expect(client.reads == 1)
}

@Test func failedWriteDropsTheCache() {
    let client = FakeClient(level: 0.5)
    let queue = DispatchQueue(label: "test.backlight.fail")
    let backlight = makeBacklight(client, queue: queue)
    client.setFailing(true)
    #expect(backlight.step(1, fine: false) == 0.5625)
    queue.sync {}
    #expect(client.reads == 1)
    // The client still holds 0.5; the next read goes to it instead of the cache.
    #expect(backlight.level() == 0.5)
    #expect(client.reads == 2)
}

@Test func setLevelRunsAfterQueuedWrites() {
    let client = FakeClient(level: 0.5)
    let queue = DispatchQueue(label: "test.backlight.order")
    let backlight = makeBacklight(client, queue: queue)
    _ = backlight.step(-1, fine: false)
    #expect(backlight.setLevel(0.2))
    // Whatever the step queued was written before (or merged away), never after setLevel.
    #expect(client.writes.last == 0.2)
    #expect(backlight.level() == 0.2)
    #expect(backlight.setLevel(1.5))
    #expect(client.writes.last == 1)
}

@Test func stepToTheTopIsCachedAtTheBound() {
    let client = FakeClient(level: 0.98)
    let queue = DispatchQueue(label: "test.backlight.top")
    let backlight = makeBacklight(client, queue: queue)
    #expect(backlight.step(1, fine: false) == 1)
    // The dispatcher's limit check reads this before the next step.
    #expect(backlight.level() == 1)
    #expect(backlight.step(1, fine: false) == 1)
    queue.sync {}
    #expect(client.reads == 1)
    #expect(client.writes.last == 1)
}
