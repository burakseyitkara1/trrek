import Foundation
import Synchronization
import Testing
import TrrekAppCore

@Test func handlesTermAndInterrupt() {
    #expect(TerminationSignals.defaultSignals == [SIGTERM, SIGINT])
}

@Test func signalRunsTheHandlerOnTheQueue() async throws {
    let received = Mutex<[Int32]>([])
    let queue = DispatchQueue(label: "test.signals")
    // SIGUSR2 stands in for SIGTERM: the wiring is the same, and an unhandled one would not end the test run.
    let signals = TerminationSignals(signals: [SIGUSR2], queue: queue) { number in
        dispatchPrecondition(condition: .onQueue(queue))
        received.withLock { $0.append(number) }
    }
    kill(getpid(), SIGUSR2)

    let deadline = Date(timeIntervalSinceNow: 3)
    while received.withLock(\.isEmpty), Date() < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(received.withLock { $0 } == [SIGUSR2])
    signals.cancel()
}
