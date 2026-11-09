import Foundation
import Testing
@testable import TrrekAppCore

/// Records the waits a retry asked for, returning at once.
final class RecordedWaits: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Duration] = []

    var all: [Duration] {
        lock.withLock { values }
    }

    var sleeper: RetrySleeper {
        { [self] duration in lock.withLock { values.append(duration) } }
    }

    var policy: RetryPolicy {
        RetryPolicy(sleep: sleeper)
    }
}

/// Which failures are retried, after how long, how often, and what the user is told about the final one.
struct RetryPolicyTests {
    private static let transient: [any Error] = [
        ReleaseFeedError.httpStatus(500), ReleaseFeedError.httpStatus(502), ReleaseFeedError.httpStatus(503),
        ReleaseFeedError.httpStatus(504), ReleaseFeedError.httpStatus(429), URLError(.timedOut),
        URLError(.networkConnectionLost), URLError(.cannotConnectToHost), URLError(.notConnectedToInternet),
        URLError(.cannotFindHost), URLError(.dnsLookupFailed)
    ]

    private static let permanent: [any Error] = [
        ReleaseFeedError.httpStatus(404), ReleaseFeedError.httpStatus(403), ReleaseFeedError.httpStatus(400),
        ReleaseFeedError.httpStatus(301), ReleaseFeedError.tooLarge, ReleaseFeedError.malformed,
        ReleaseFeedError.unexpectedLink, ReleaseFeedError.missingTag, CancellationError(), URLError(.cancelled),
        URLError(.dataNotAllowed), URLError(.secureConnectionFailed), URLError(.badServerResponse),
        UpdateInstallError.verification(.signature), UpdateVerificationFailure.notNotarized, CocoaError(.fileNoSuchFile)
    ]

    @Test func onlyTransientFailuresAreRetried() {
        for error in Self.transient {
            #expect(UpdateFailure.isTransient(error), "\(error)")
        }
        for error in Self.permanent {
            #expect(!UpdateFailure.isTransient(error), "\(error)")
        }
    }

    @Test func retriesWaitTwoThenFiveSecondsAndStopAfterTwo() {
        let policy = RetryPolicy()
        let error = URLError(.timedOut)
        #expect(policy.delay(after: error, retry: 0) == .seconds(2))
        #expect(policy.delay(after: error, retry: 1) == .seconds(5))
        #expect(policy.delay(after: error, retry: 2) == nil)
        #expect(policy.delay(after: ReleaseFeedError.httpStatus(404), retry: 0) == nil)
        #expect(RetryPolicy.never.delay(after: error, retry: 0) == nil)
    }

    @Test func retryAfterIsWaitedUpToThirtySeconds() {
        let policy = RetryPolicy()
        #expect(policy.delay(after: ReleaseFeedError.httpStatus(503, retryAfter: 10), retry: 0) == .seconds(10))
        #expect(policy.delay(after: ReleaseFeedError.httpStatus(429, retryAfter: 30), retry: 1) == .seconds(30))
        #expect(policy.delay(after: ReleaseFeedError.httpStatus(429, retryAfter: 0), retry: 0) == .zero)
        // A longer wait ends the attempts; the failure then says to try again in a few minutes.
        #expect(policy.delay(after: ReleaseFeedError.httpStatus(503, retryAfter: 31), retry: 0) == nil)
        #expect(policy.delay(after: ReleaseFeedError.httpStatus(503, retryAfter: 10), retry: 2) == nil)
    }

    @Test func retryAfterIsReadFromSecondsOrADate() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(ReleaseFeedClient.retryAfter("12", now: now) == 12)
        #expect(ReleaseFeedClient.retryAfter(" 0 ", now: now) == 0)
        #expect(ReleaseFeedClient.retryAfter("-3", now: now) == nil)
        #expect(ReleaseFeedClient.retryAfter("soon", now: now) == nil)
        // 1_800_000_000 is Fri, 15 Jan 2027 08:00:00 GMT.
        #expect(ReleaseFeedClient.retryAfter("Fri, 15 Jan 2027 08:00:20 GMT", now: now) == 20)
        #expect(ReleaseFeedClient.retryAfter("Fri, 15 Jan 2027 07:59:00 GMT", now: now) == 0)

        let url = try #require(URL(string: "https://example.com"))
        func status(_ code: Int, retryAfter: String) throws -> ReleaseFeedError? {
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: code,
                httpVersion: nil,
                headerFields: ["Retry-After": retryAfter]
            ))
            do {
                try ReleaseFeedClient.requireSuccess(response, now: now)
                return nil
            } catch {
                return error
            }
        }
        #expect(try status(503, retryAfter: "7") == .httpStatus(503, retryAfter: 7))
        #expect(try status(429, retryAfter: "7") == .httpStatus(429, retryAfter: 7))
        #expect(try status(504, retryAfter: "7") == .httpStatus(504))
        #expect(try status(404, retryAfter: "7") == .httpStatus(404))
    }

    @Test func runRetriesUntilSuccess() async throws {
        let waits = RecordedWaits()
        var attempts = 0
        var restarts = 0
        let value = try await waits.policy.run(
            "test",
            onRetry: { restarts += 1 },
            operation: { () async throws -> Int in
                attempts += 1
                if attempts < 3 {
                    throw ReleaseFeedError.httpStatus(504)
                }
                return 42
            }
        )
        #expect(value == 42)
        #expect(attempts == 3)
        #expect(restarts == 2)
        #expect(waits.all == [.seconds(2), .seconds(5)])
    }

    @Test func runGivesUpAfterThreeAttempts() async {
        let waits = RecordedWaits()
        var attempts = 0
        await #expect(throws: URLError(.timedOut)) {
            try await waits.policy.run("test") { () async throws -> Int in
                attempts += 1
                throw URLError(.timedOut)
            }
        }
        #expect(attempts == 3)
        #expect(waits.all.count == 2)
    }

    @Test func runDoesNotRetryAPermanentFailure() async {
        let waits = RecordedWaits()
        var attempts = 0
        await #expect(throws: ReleaseFeedError.tooLarge) {
            try await waits.policy.run("test") { () async throws -> Int in
                attempts += 1
                throw ReleaseFeedError.tooLarge
            }
        }
        #expect(attempts == 1)
        #expect(waits.all.isEmpty)
    }

    @Test func cancellationStopsRetrying() async {
        // Cancelled while the attempt runs: its transient failure is not retried.
        let waits = RecordedWaits()
        let task = Task {
            var attempts = 0
            do {
                _ = try await waits.policy.run("test") { () async throws -> Int in
                    attempts += 1
                    withUnsafeCurrentTask { $0?.cancel() }
                    throw URLError(.timedOut)
                }
            } catch {}
            return attempts
        }
        #expect(await task.value == 1)
        #expect(waits.all.isEmpty)

        // Cancelled during the wait: the wait throws and nothing is tried again.
        let cancelled = RetryPolicy(sleep: { _ in throw CancellationError() })
        var attempts = 0
        await #expect(throws: CancellationError.self) {
            try await cancelled.run("test") { () async throws -> Int in
                attempts += 1
                throw URLError(.networkConnectionLost)
            }
        }
        #expect(attempts == 1)
    }

    @Test func failuresAreClassified() {
        #expect(UpdateFailure(ReleaseFeedError.httpStatus(504)) == .serverUnavailable)
        #expect(UpdateFailure(ReleaseFeedError.httpStatus(429)) == .serverUnavailable)
        #expect(UpdateFailure(URLError(.timedOut)) == .serverUnavailable)
        #expect(UpdateFailure(URLError(.cannotConnectToHost)) == .serverUnavailable)
        #expect(UpdateFailure(URLError(.networkConnectionLost)) == .serverUnavailable)
        #expect(UpdateFailure(URLError(.notConnectedToInternet)) == .offline)
        #expect(UpdateFailure(URLError(.cannotFindHost)) == .offline)
        #expect(UpdateFailure(URLError(.dataNotAllowed)) == .offline)
        #expect(UpdateFailure(UpdateInstallError.verification(.olderThanRunning)) == .verification)
        #expect(UpdateFailure(UpdateVerificationFailure.signature) == .verification)
        #expect(UpdateFailure(ReleaseFeedError.httpStatus(404)) == .other)
        #expect(UpdateFailure(ReleaseFeedError.tooLarge) == .other)
        #expect(UpdateFailure(UpdateInstallError.extraction) == .other)
        #expect(UpdateFailure(CocoaError(.fileWriteNoPermission)) == .other)
    }

    @Test func reasonsHaveTheirTexts() {
        #expect(UpdateFailure.serverUnavailable.reason == "GitHub isn’t responding. Try again in a few minutes.")
        #expect(UpdateFailure.offline.reason == "You appear to be offline.")
        #expect(UpdateFailure.verification.reason
            == "The downloaded update couldn’t be verified, so it wasn’t installed.")
        #expect(UpdateFailure.other.reason == nil)

        let version = SemanticVersion(major: 0, minor: 5, patch: 1)
        let failed = UpdateRowState.failed(version, reason: .offline)
        #expect(failed.title == "Update Failed — Try Again")
        #expect(failed.statusText == "The update failed.")
        #expect(failed.failureReason == "You appear to be offline.")
        #expect(UpdateRowState.failed(version).failureReason == nil)
        #expect(UpdateRowState.available(version).failureReason == nil)

        var row = UpdateRowState.downloading(version, progress: 0.4)
        row.fail(.serverUnavailable)
        #expect(row == .failed(version, reason: .serverUnavailable))
        let started = row.start()
        #expect(started)
        #expect(row == .downloading(version, progress: nil))
    }

    /// A failed check's alert uses General's words for an unavailable server or a missing network.
    @MainActor
    @Test func checkFailuresUseTheSameWords() {
        #expect(UpdateChecker.message(for: ReleaseFeedError.httpStatus(502))
            == "GitHub isn’t responding. Try again in a few minutes.")
        #expect(UpdateChecker.message(for: URLError(.timedOut))
            == "GitHub isn’t responding. Try again in a few minutes.")
        #expect(UpdateChecker.message(for: URLError(.notConnectedToInternet)) == "You appear to be offline.")
        #expect(UpdateChecker.message(for: ReleaseFeedError.malformed) == ReleaseFeedError.malformed.message)
        #expect(UpdateChecker.message(for: ReleaseFeedError.httpStatus(404)) == "The server answered with status 404.")
    }
}
