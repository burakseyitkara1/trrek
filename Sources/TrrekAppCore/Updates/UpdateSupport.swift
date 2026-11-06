import Foundation
import Security

/// Runs blocking work on a global queue, so neither the main actor nor the cooperative pool waits for it.
func runOffMain<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(with: Result { try work() })
        }
    }
}

/// Runs a system command line tool and returns its exit status and standard output (standard error is discarded).
enum CommandRunner {
    struct Output: Sendable {
        let status: Int32
        let output: Data
    }

    /// A tool still running after this long is sent SIGTERM, and SIGKILL `killGrace` later (one-shot work items, not
    /// a repeating timer).
    static let timeout: TimeInterval = 120
    static let killGrace: TimeInterval = 5

    /// Standard output goes to a temporary file rather than a pipe, so a helper process that inherited it cannot keep
    /// the call waiting once the tool itself has exited.
    static func run(
        _ tool: String,
        _ arguments: [String],
        timeout: TimeInterval = timeout,
        killGrace: TimeInterval = killGrace
    ) async throws -> Output {
        try await runOffMain {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("trrek-out-\(UUID().uuidString)")
            guard FileManager.default.createFile(atPath: file.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            defer { try? FileManager.default.removeItem(at: file) }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardOutput = handle
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            try process.run()
            let watchdog = Watchdog(pid: process.processIdentifier)
            watchdog.arm(after: timeout, grace: killGrace)
            process.waitUntilExit()
            watchdog.disarm()
            return try Output(status: process.terminationStatus, output: Data(contentsOf: file))
        }
    }

    /// Signals a process once its time is up, unless it was disarmed first.
    private final class Watchdog: @unchecked Sendable {
        private let pid: pid_t
        private let lock = NSLock()
        private var armed = true

        init(pid: pid_t) {
            self.pid = pid
        }

        func arm(after timeout: TimeInterval, grace: TimeInterval) {
            let queue = DispatchQueue.global()
            queue.asyncAfter(deadline: .now() + timeout) { self.signal(SIGTERM) }
            queue.asyncAfter(deadline: .now() + timeout + grace) { self.signal(SIGKILL) }
        }

        func disarm() {
            lock.withLock { armed = false }
        }

        private func signal(_ number: Int32) {
            lock.withLock {
                guard armed else { return }
                appLogger.error("command \(self.pid, privacy: .public) timed out; signal \(number, privacy: .public)")
                kill(pid, number)
            }
        }
    }
}

/// Developer ID Application certificates of the release team, the part of the requirements shared by the app and
/// the disk image.
enum ReleaseSigner {
    static let developerID = """
    anchor apple generic \
    and certificate 1[field.1.2.840.113635.100.6.2.6] exists \
    and certificate leaf[field.1.2.840.113635.100.6.1.13] exists \
    and certificate leaf[subject.OU] = "R2333A9MFR"
    """

    /// Whether the code at `url` is validly signed and meets `requirement`; logs the status otherwise.
    static func satisfies(_ url: URL, _ requirement: String, flags: SecCSFlags = [], label: String) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return false }
        var compiled: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &compiled) == errSecSuccess,
              let compiled
        else { return false }
        let status = SecStaticCodeCheckValidity(code, flags, compiled)
        if status != errSecSuccess {
            appLogger.error("update \(label, privacy: .public) check failed: \(status, privacy: .public)")
        }
        return status == errSecSuccess
    }
}
