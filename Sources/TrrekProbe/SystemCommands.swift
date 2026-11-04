import CoreGraphics
import Foundation
import TrrekPlatform

// MARK: - backlight

func runBacklight(_ options: [String]) {
    guard let action = options.first, ["get", "up", "down", "bench"].contains(action) else {
        usageError("backlight needs one of: get, up, down, bench")
    }
    guard let backlight = KeyboardBacklight() else {
        output("unavailable")
        exit(action == "get" ? 0 : 1)
    }
    if action == "bench" {
        runBacklightBench(backlight)
        return
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

/// Times 50 read+write cycles of the backlight level and restores the starting level. The raw cycle reads the
/// client and writes synchronously (the cost before the cache); the step cycle is what a slide step costs on the
/// frame thread (`level()` then `step`, from the cache, with the write queued). Directions alternate, one fine step
/// at a time, so the level stays near where it was.
private func runBacklightBench(_ backlight: KeyboardBacklight) {
    let cycles = 50
    guard let start = backlight.readLevelUncached() else {
        output("failed: level unreadable")
        exit(1)
    }
    // Start away from the nearer bound so the alternating writes are never clamped.
    let first = start > 0.5 ? -1 : 1
    var failures = 0
    let raw = timeCycles(cycles, first: first) { direction in
        let current = backlight.readLevelUncached() ?? start
        if !backlight.setLevel(current + Float(direction) / 64) {
            failures += 1
        }
    }
    backlight.setLevel(start)
    let step = timeCycles(cycles, first: first) { direction in
        _ = backlight.level()
        if backlight.step(direction, fine: true) == nil {
            failures += 1
        }
    }
    let restored = backlight.setLevel(start)
    output("raw read+write (\(cycles) cycles): " + raw.description)
    output("step from cache (\(cycles) cycles): " + step.description)
    output(String(format: "failures=%d restored=%.4f %@", failures, start, restored ? "ok" : "failed"))
}

private struct Timings {
    let samples: [Double]

    var description: String {
        let average = samples.reduce(0, +) / Double(max(samples.count, 1))
        return String(format: "min=%.3f ms avg=%.3f ms max=%.3f ms", samples.min() ?? 0, average, samples.max() ?? 0)
    }
}

/// Runs `body` `count` times with alternating directions and returns each run's duration in milliseconds.
private func timeCycles(_ count: Int, first: Int, _ body: (Int) -> Void) -> Timings {
    var samples: [Double] = []
    samples.reserveCapacity(count)
    var direction = first
    for _ in 0 ..< count {
        let begin = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        body(direction)
        let end = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        samples.append(Double(end - begin) / 1_000_000)
        direction = -direction
    }
    return Timings(samples: samples)
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
    // The callbacks run on the main thread, where the monitor lives.
    nonisolated(unsafe) let events = monitor
    // `arrival` is the system uptime when the event reached the tap, which is what trrek uses; `event` is the
    // timestamp the event carries, shown for comparison only.
    monitor.onKeyDown = { time in
        MainActor.assumeIsolated {
            output(String(format: "arrival=%.4f event=%.4f keyDown", time, events.lastEventTimestamp))
        }
    }
    monitor.onFlagsChanged = { flags, time in
        MainActor.assumeIsolated {
            output(String(format: "arrival=%.4f event=%.4f flagsChanged ", time, events.lastEventTimestamp)
                + String(format: "0x%llx ", flags.rawValue) + modifierDescription(flags))
        }
    }
    monitor.onMouseDown = { time in
        MainActor.assumeIsolated {
            output(String(format: "arrival=%.4f event=%.4f mouseDown", time, events.lastEventTimestamp))
        }
    }
    monitor.start()
    output("listening for \(seconds) s; events posted by trrek are not shown")
    pumpRunLoop(until: Date().addingTimeInterval(seconds))
    monitor.stop()
    output("stopped")
}
