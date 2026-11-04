import Foundation
import Testing
@testable import Trrek

@MainActor
struct RelauncherTests {
    @Test func passesThePidAndPathAsParameters() {
        let arguments = Relauncher.arguments(pid: 4242, bundlePath: "/Users/me/Applications/it's here/trrek.app")
        #expect(arguments.count == 5)
        #expect(arguments[0] == "-c")
        #expect(arguments[2] == "trrek-relaunch")
        #expect(arguments[3] == "4242")
        #expect(arguments[4] == "/Users/me/Applications/it's here/trrek.app")
        // The path never enters the script text.
        #expect(!arguments[1].contains("trrek.app"))
        #expect(arguments[1].contains("kill -0 \"$1\""))
        #expect(arguments[1].hasSuffix("exec /usr/bin/open \"$2\""))
    }

    /// Runs the script against a live process, with a harmless command in place of `open`: the command runs only
    /// once that process has exited.
    @Test func scriptWaitsForTheProcessThenRuns() throws {
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["0.5"]
        try sleeper.run()

        let script = Relauncher.arguments(pid: 0, bundlePath: "")[1]
            .replacingOccurrences(of: "exec /usr/bin/open \"$2\"", with: "printf '%s' \"$2\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "trrek-relaunch", String(sleeper.processIdentifier), "opened"]
        let pipe = Pipe()
        process.standardOutput = pipe
        let start = Date()
        try process.run()
        process.waitUntilExit()
        let elapsed = Date().timeIntervalSince(start)
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)

        #expect(process.terminationStatus == 0)
        #expect(output == "opened")
        // The sleeper exits after 0.5 s; the script polls every 0.1 s, so it cannot finish much earlier.
        #expect(elapsed >= 0.35)
        #expect(!sleeper.isRunning)
    }

    /// A process that is already gone does not hold the command up.
    @Test func scriptRunsAtOnceWhenTheProcessIsGone() throws {
        let script = Relauncher.arguments(pid: 0, bundlePath: "")[1]
            .replacingOccurrences(of: "exec /usr/bin/open \"$2\"", with: "printf '%s' \"$2\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // A pid that cannot exist.
        process.arguments = ["-c", script, "trrek-relaunch", "99999999", "opened"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        #expect(output == "opened")
    }

    @Test func aBareExecutableCannotRelaunch() {
        // Tests run from the test runner, not from an app bundle.
        #expect(!Relauncher.canRelaunch)
    }
}
