import Foundation

/// Polls `done` until it holds or `timeout` passes. Sleeping suspends the test, so the main queue drains between
/// polls: main-actor work, deferred view teardown and `DispatchQueue.main` blocks all get to run. A nested run
/// loop spin would not do that, since the test itself runs as a main-queue job.
@MainActor
func waitUntil(timeout: TimeInterval = 10, _ done: () -> Bool) async throws {
    let deadline = Date(timeIntervalSinceNow: timeout)
    while !done(), Date() < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
}
