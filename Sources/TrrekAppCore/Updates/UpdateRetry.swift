import Foundation
import TrrekPlatform

/// Waits before a retry; tests pass one that returns at once. Throws `CancellationError` when the task is cancelled.
public typealias RetrySleeper = @Sendable (Duration) async throws -> Void

/// Retries the feed request and the disk image download after a transient failure: a 5xx or 429 answer, or a
/// network error that may clear within seconds. At most `delays.count` retries follow the first try, after 2 s and
/// then 5 s; a 429 or 503 answer's `Retry-After` of up to `maximumRetryAfter` is waited instead, and a longer one
/// ends the attempts. Each wait is a one-shot `Task.sleep`, never a timer.
public struct RetryPolicy: Sendable {
    public static let standardDelays: [Duration] = [.seconds(2), .seconds(5)]
    public static let maximumRetryAfter = 30

    /// The wait before each retry; its count is the number of retries.
    public let delays: [Duration]
    /// The longest `Retry-After` (seconds) waited for.
    public let maximumRetryAfter: Int
    public let sleep: RetrySleeper

    public init(
        delays: [Duration] = RetryPolicy.standardDelays,
        maximumRetryAfter: Int = RetryPolicy.maximumRetryAfter,
        sleep: @escaping RetrySleeper = { try await Task.sleep(for: $0) }
    ) {
        self.delays = delays
        self.maximumRetryAfter = maximumRetryAfter
        self.sleep = sleep
    }

    /// No retries: the first failure is final.
    public static let never = RetryPolicy(delays: [])

    /// The wait before retry number `retry` (0 for the first) after `error`; `nil` when it must not be retried.
    public func delay(after error: any Error, retry: Int) -> Duration? {
        guard retry >= 0, retry < delays.count, UpdateFailure.isTransient(error) else { return nil }
        if case let .httpStatus(_, retryAfter?) = error as? ReleaseFeedError {
            guard retryAfter <= maximumRetryAfter else { return nil }
            return .seconds(max(retryAfter, 0))
        }
        return delays[retry]
    }

    /// Runs `operation` until it succeeds, fails for good or the retries run out; the last error is thrown. `label`
    /// names it in the log ("update <label> failed: …"). `onRetry` is called once a retry is decided, before its wait.
    /// Cancellation, also during a wait, ends it at once.
    public func run<T>(
        _ label: String,
        onRetry: () -> Void = {},
        operation: () async throws -> T
    ) async throws -> T {
        var retry = 0
        while true {
            do {
                return try await operation()
            } catch {
                guard !Task.isCancelled, let delay = delay(after: error, retry: retry) else { throw error }
                // A feed error names only a status; anything else may carry an address, so only its code is public.
                let cause = (error as? ReleaseFeedError).map { String(describing: $0) } ?? error.domainAndCode
                let next = "retry \(retry + 1) in \(delay)"
                appLogger.notice(
                    "update \(label, privacy: .public) failed: \(cause, privacy: .public); \(next, privacy: .public)"
                )
                // Before the wait, so the row shows the restart (no stale progress) while it waits.
                onRetry()
                try await sleep(delay)
                retry += 1
            }
        }
    }
}

/// Why an update check or download finally failed, as the user is told.
public enum UpdateFailure: Equatable, Sendable {
    /// The server answered 5xx or 429, timed out (also the whole download's time limit) or dropped the connection,
    /// also after the retries.
    case serverUnavailable
    /// The Mac is not connected, or the server's name could not be looked up.
    case offline
    /// The downloaded update failed its signature, notarization, identity or version check.
    case verification
    case other

    /// Classifies a check or download error. A verification failure of the install is classified by the caller.
    public init(_ error: any Error) {
        if let error = error as? ReleaseFeedError {
            if case let .httpStatus(status, _) = error, Self.isServerStatus(status) {
                self = .serverUnavailable
            } else {
                self = .other
            }
            return
        }
        if let error = error as? UpdateInstallError {
            if case .verification = error {
                self = .verification
            } else {
                self = .other
            }
            return
        }
        if error is UpdateVerificationFailure {
            self = .verification
            return
        }
        if error is DownloadTimeLimitReached {
            self = .serverUnavailable
            return
        }
        if let code = (error as? URLError)?.code {
            if Self.offlineCodes.contains(code) {
                self = .offline
            } else if Self.unavailableCodes.contains(code) {
                self = .serverUnavailable
            } else {
                self = .other
            }
            return
        }
        self = .other
    }

    /// The server is overloaded or failing for now.
    static func isServerStatus(_ status: Int) -> Bool {
        status == 429 || (500 ... 599).contains(status)
    }

    /// The network or the server was briefly unavailable.
    static let unavailableCodes: Set<URLError.Code> = [.timedOut, .networkConnectionLost, .cannotConnectToHost]
    /// No usable network, or the name lookup failed.
    static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .cannotFindHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff
    ]
    /// The offline codes that may clear within seconds (Wi-Fi joining after wake); cellular data that is turned off
    /// does not.
    static let recoverableOfflineCodes: Set<URLError.Code> = [
        .notConnectedToInternet,
        .cannotFindHost,
        .dnsLookupFailed
    ]

    /// Whether `error` is worth retrying: a 5xx or 429 answer, or a network error that may clear within seconds.
    /// Cancellation, refused content (too large, malformed, unexpected links), verification and other 4xx answers
    /// are never retried.
    public static func isTransient(_ error: any Error) -> Bool {
        if error is CancellationError {
            return false
        }
        if case let .httpStatus(status, _) = error as? ReleaseFeedError {
            return isServerStatus(status)
        }
        guard let code = (error as? URLError)?.code else { return false }
        return unavailableCodes.contains(code) || recoverableOfflineCodes.contains(code)
    }

    /// The line under the failed update in General; `nil` for `other`, which the row's own text already says.
    public var reason: String? {
        switch self {
        case .serverUnavailable:
            String(localized: "GitHub isn’t responding. Try again in a few minutes.", bundle: .main)
        case .offline:
            String(localized: "You appear to be offline.", bundle: .main)
        case .verification:
            String(localized: "The downloaded update couldn’t be verified, so it wasn’t installed.", bundle: .main)
        case .other:
            nil
        }
    }
}
