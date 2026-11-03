import CoreGraphics
import Foundation
import TrrekPlatform

// MARK: - backlight

func runBacklight(_ options: [String]) {
    guard let action = options.first, ["get", "up", "down"].contains(action) else {
        usageError("backlight needs one of: get, up, down")
    }
    guard let backlight = KeyboardBacklight() else {
        output("unavailable")
        exit(action == "get" ? 0 : 1)
    }
    let level: Float? = switch action {
    case "up": backlight.step(1, fine: false)
    case "down": backlight.step(-1, fine: false)
    default: backlight.level()
    }
    guard let level else {
        output("failed")
        exit(1)
    }
    output(String(format: "%.4f", level))
}

// MARK: - keys

private let modifierNames: [(CGEventFlags, String)] = [
    (.maskShift, "shift"), (.maskControl, "control"), (.maskAlternate, "option"), (.maskCommand, "command"),
    (.maskAlphaShift, "capslock"), (.maskSecondaryFn, "fn")
]

private func modifierDescription(_ flags: CGEventFlags) -> String {
    let names = modifierNames.filter { flags.contains($0.0) }.map(\.1)
    return names.isEmpty ? "none" : names.joined(separator: "+")
}

@MainActor
func runKeys(_ options: [String]) {
    var seconds = 10.0
    if let value = options.first {
        guard let parsed = Double(value), parsed > 0 else { usageError("invalid seconds: \(value)") }
        seconds = parsed
    }
    let monitor = InputMonitor()
    guard monitor.isAvailable else {
        output("event tap could not be created: grant Accessibility to the terminal running this tool in "
            + "System Settings > Privacy & Security > Accessibility")
        exit(1)
    }
    // Event times are seconds of system uptime; the uptime when the line is printed is shown for comparison.
    monitor.onKeyDown = { time in
        output(String(format: "t=%.4f uptime=%.4f keyDown", time, ProcessInfo.processInfo.systemUptime))
    }
    monitor.onFlagsChanged = { flags, time in
        output(String(format: "t=%.4f uptime=%.4f flagsChanged ", time, ProcessInfo.processInfo.systemUptime)
            + String(format: "0x%llx ", flags.rawValue) + modifierDescription(flags))
    }
    monitor.start()
    output("listening for \(seconds) s; events posted by trrek are not shown")
    pumpRunLoop(until: Date().addingTimeInterval(seconds))
    monitor.stop()
    output("stopped")
}
