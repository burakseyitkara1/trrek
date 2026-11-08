import Foundation
import Testing

/// Polls `done` until it holds or `timeout` passes. Sleeping suspends the test, so the main queue drains between
/// polls: main-actor work, deferred view teardown and `DispatchQueue.main` blocks all get to run. A nested run
/// loop spin would not do that, since the test itself runs as a main-queue job. Running out of time is recorded as
/// a test issue, so a wait that never ends shows up as such rather than as a later, puzzling expectation.
@MainActor
func waitUntil(
    timeout: TimeInterval = 10,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ done: () -> Bool
) async throws {
    let deadline = Date(timeIntervalSinceNow: timeout)
    while !done(), Date() < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
    if !done() {
        Issue.record("waited \(timeout) s and the condition still did not hold", sourceLocation: sourceLocation)
    }
}
