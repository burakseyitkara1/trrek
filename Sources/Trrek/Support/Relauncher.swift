import AppKit
import TrrekAppCore

/// Quits trrek and opens the same app bundle again, so a new interface language takes effect.
///
/// A short-lived shell waits for this process to exit before opening the bundle: opening it while trrek still runs
/// would only bring the running instance to the front (which shows its settings window). The wait is capped, after
/// which the bundle is opened anyway.
@MainActor
enum Relauncher {
    /// How long the shell waits for trrek to exit, in tenths of a second.
    static let waitLimit = 100

    /// Whether trrek runs from an app bundle; a bare executable (a development build) cannot be reopened.
    static var canRelaunch: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    /// The shell command line that waits for `pid` to exit and opens `bundlePath`. The values are passed as
    /// positional parameters, never spliced into the script.
    static func arguments(pid: Int32, bundlePath: String) -> [String] {
        let running = "kill -0 \"$1\" 2>/dev/null && [ \"$i\" -lt \(waitLimit) ]"
        let script = "i=0; while \(running); do sleep 0.1; i=$((i+1)); done; exec /usr/bin/open \"$2\""
        return ["-c", script, "trrek-relaunch", String(pid), bundlePath]
    }

    /// Starts the waiting shell and quits. Does nothing (and logs) when the shell cannot be started.
    static func relaunch() {
        guard canRelaunch else {
            appLogger.error("relaunch skipped: not running from an app bundle")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = arguments(
            pid: ProcessInfo.processInfo.processIdentifier,
            bundlePath: Bundle.main.bundleURL.path
        )
        do {
            try process.run()
        } catch {
            appLogger.error("relaunch failed: \(String(describing: error), privacy: .public)")
            return
        }
        appLogger.notice("relaunching for a new language")
        NSApp.terminate(nil)
    }
}
