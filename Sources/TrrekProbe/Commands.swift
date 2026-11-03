import CMultitouch
import CoreGraphics
import Darwin
import Foundation
import TrrekEngine
import TrrekPlatform

// MARK: - Output

/// Writes a line straight to standard output so lines from the frame thread are not buffered.
func output(_ line: String) {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

func printUsage() {
    output("""
    usage: trrek-probe <command> [arguments]

    commands:
      devices                 list multitouch devices (built-in, surface size, multitouch ID)
      frames [seconds]        print raw contact frames (default 10 s)
      layout-check            validate the contact struct layout against the first 50 frames
      haptic <id> [repeat]    play haptic waveform <id> on the built-in trackpad
      key <name> [--fine]     post a media key: \(mediaKeyNames.joined(separator: "|"))
      switcher                hold Command, press Tab twice, release (needs Accessibility)
      freeze <seconds>        swallow pointer movement and scroll for a while (needs Accessibility)
      mem                     print this process's memory footprint in MB
      pipeline [seconds]      print every engine command from live frames; sends nothing (default 20 s)
      backlight get|up|down   read or step the keyboard backlight level (0...1)
      keys [seconds]          print user key-down and modifier events (default 10 s; needs Accessibility)
    """)
}

func usageError(_ message: String) -> Never {
    output(message)
    printUsage()
    exit(64)
}

/// Pumps the main run loop until `deadline` or until `done` returns true.
func pumpRunLoop(until deadline: Date, done: () -> Bool = { false }) {
    while Date() < deadline, !done() {
        _ = CFRunLoopRunInMode(.defaultMode, 0.05, false)
    }
}

private func startStream(_ stream: RawFrameStream) {
    do {
        try stream.start()
    } catch {
        output("cannot start frame stream: \(error)")
        exit(1)
    }
}

private func touchDescription(_ touch: MTTouch) -> String {
    String(
        format: "id=%d state=%d nx=%.3f ny=%.3f major=%.2f minor=%.2f",
        touch.identifier, touch.state, touch.nx, touch.ny, touch.majorAxis, touch.minorAxis
    )
}

// MARK: - devices

func runDevices() {
    output("multitouch symbols: \(PrivateSymbols.multitouch == nil ? "MISSING" : "ok")")
    output("actuator symbols: \(PrivateSymbols.actuator == nil ? "MISSING" : "ok")")
    let devices = MultitouchDevices.enumerate()
    output("devices: \(devices.count)")
    for (index, device) in devices.enumerated() {
        var rawWidth: Int32 = 0
        var rawHeight: Int32 = 0
        if let symbols = PrivateSymbols.multitouch {
            _ = symbols.surfaceDimensions(device.ref, &rawWidth, &rawHeight)
        }
        let size = String(format: "%.2f x %.2f mm", device.widthMM, device.heightMM)
        let identifier = device.multitouchID.map { String(format: "0x%llx (%llu)", $0, $0) } ?? "none"
        output("[\(index)] built-in=\(device.isBuiltIn) raw=\(rawWidth)x\(rawHeight) size(raw/100)=\(size) "
            + "multitouch-id=\(identifier)")
    }
}

// MARK: - frames

func runFrames(_ options: [String]) {
    var seconds = 10.0
    if let value = options.first {
        guard let parsed = Double(value), parsed > 0 else { usageError("invalid seconds: \(value)") }
        seconds = parsed
    }
    let devices = MultitouchDevices.enumerate()
    let stream = RawFrameStream(devices: devices)
    stream.onFrame = { _, touches, timestamp in
        var line = String(format: "t=%.4f n=%d", timestamp, touches.count)
        for touch in touches {
            line += " | " + touchDescription(touch)
        }
        output(line)
    }
    startStream(stream)
    output("streaming \(devices.count) device(s) for \(seconds) s")
    pumpRunLoop(until: Date().addingTimeInterval(seconds))
    stream.stop()
}

// MARK: - layout-check

private final class FrameCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [[MTTouch]] = []
    private let limit: Int

    init(limit: Int) {
        self.limit = limit
    }

    func add(_ touches: UnsafeBufferPointer<MTTouch>) {
        guard !touches.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        if frames.count < limit {
            frames.append(Array(touches))
        }
    }

    var snapshot: [[MTTouch]] {
        lock.lock()
        defer { lock.unlock() }
        return frames
    }
}

private func layoutProblem(_ touch: MTTouch) -> String? {
    if !(0 ... 1).contains(touch.nx) || !(0 ... 1).contains(touch.ny) {
        return "normalized position out of [0, 1]"
    }
    if !(touch.majorAxis > 0 && touch.majorAxis < 100) {
        return "majorAxis out of (0, 100)"
    }
    if !(0 ... 7).contains(touch.state) {
        return "state out of 0...7"
    }
    return nil
}

func runLayoutCheck() {
    let frameLimit = 50
    let collector = FrameCollector(limit: frameLimit)
    let stream = RawFrameStream(devices: MultitouchDevices.enumerate())
    stream.onFrame = { _, touches, _ in collector.add(touches) }
    startStream(stream)
    output("touch the trackpad and move a finger...")

    pumpRunLoop(until: Date().addingTimeInterval(10)) { !collector.snapshot.isEmpty }
    if collector.snapshot.isEmpty {
        stream.stop()
        output("NO FRAMES")
        exit(2)
    }
    pumpRunLoop(until: Date().addingTimeInterval(10)) { collector.snapshot.count >= frameLimit }
    stream.stop()

    let frames = collector.snapshot
    let touches = frames.flatMap(\.self)
    if let first = touches.first {
        output("first contact: " + touchDescription(first) + String(
            format: " finger=%d hand=%d total=%.3f pressure=%.3f angle=%.3f density=%.3f",
            first.fingerID, first.handID, first.total, first.pressure, first.angle, first.density
        ))
    }
    for touch in touches {
        if let problem = layoutProblem(touch) {
            output("MISMATCH: \(problem): " + touchDescription(touch))
            exit(1)
        }
    }
    output("OK (\(frames.count) frames, \(touches.count) contacts)")
}

// MARK: - haptic

func runHaptic(_ options: [String]) {
    guard let value = options.first, let waveform = Int32(value) else { usageError("haptic needs a waveform id") }
    var count = 1
    if options.count > 1 {
        guard let parsed = Int(options[1]), parsed > 0 else { usageError("invalid repeat: \(options[1])") }
        count = parsed
    }
    let devices = MultitouchDevices.enumerate()
    guard let device = devices.first(where: \.isBuiltIn) ?? devices.first,
          let identifier = device.multitouchID
    else {
        output("no device with a multitouch ID")
        exit(1)
    }
    guard let haptics = ActuatorHaptics(multitouchID: identifier) else {
        output("actuator unavailable for multitouch ID \(identifier)")
        exit(1)
    }
    for index in 0 ..< count {
        output("actuate \(waveform) #\(index + 1): \(haptics.actuate(waveform: waveform) ? "ok" : "failed")")
        if index + 1 < count {
            Thread.sleep(forTimeInterval: 0.3)
        }
    }
}

// MARK: - key

private let mediaKeys: [(String, MediaKey)] = [
    ("soundUp", .soundUp), ("soundDown", .soundDown),
    ("brightnessUp", .brightnessUp), ("brightnessDown", .brightnessDown),
    ("mute", .mute), ("play", .play), ("next", .next), ("previous", .previous),
    ("illuminationUp", .illuminationUp), ("illuminationDown", .illuminationDown)
]

private var mediaKeyNames: [String] {
    mediaKeys.map(\.0)
}

func runKey(_ options: [String]) {
    guard let name = options.first, let key = mediaKeys.first(where: { $0.0 == name })?.1 else {
        usageError("key needs one of: \(mediaKeyNames.joined(separator: ", "))")
    }
    let fine = options.dropFirst().contains("--fine")
    output("accessibility trusted: \(Permissions.isTrusted)")
    MediaKeyPoster.post(key, fine: fine)
    output("posted \(name)\(fine ? " (fine)" : "")")
}

// MARK: - switcher

func requireTrust() {
    guard Permissions.isTrusted else {
        output("accessibility permission is required: grant it to the terminal running this tool in "
            + "System Settings > Privacy & Security > Accessibility")
        exit(1)
    }
}

func runSwitcher() {
    requireTrust()
    let command: CGKeyCode = 55
    let tab: CGKeyCode = 48
    KeyPoster.modifierDown(command, flags: .maskCommand)
    Thread.sleep(forTimeInterval: 0.5)
    KeyPoster.press(keyCode: tab, flags: .maskCommand)
    Thread.sleep(forTimeInterval: 0.5)
    KeyPoster.press(keyCode: tab, flags: .maskCommand)
    Thread.sleep(forTimeInterval: 0.5)
    KeyPoster.modifierUp(command)
    output("switcher sequence posted")
}

// MARK: - freeze

@MainActor
func runFreeze(_ options: [String]) {
    guard let value = options.first, let seconds = Double(value), seconds > 0 else {
        usageError("freeze needs a duration in seconds")
    }
    requireTrust()
    let guardTap = EventTapGuard()
    guard guardTap.isAvailable else {
        output("event tap could not be created")
        exit(1)
    }
    guardTap.setFreeze(true)
    output("cursor frozen for \(seconds) s")
    pumpRunLoop(until: Date().addingTimeInterval(seconds))
    guardTap.setFreeze(false)
    output("cursor released")
}

// MARK: - pipeline

/// Prints engine commands instead of carrying them out.
private final class LoggingSink: CommandSink, @unchecked Sendable {
    func handle(_ command: GestureCommand, device: UInt64) {
        output(String(format: "%.3f ", ProcessInfo.processInfo.systemUptime) + "\(command) device=\(device)")
    }
}

/// Records the first frame's timestamp next to the system clocks read when it arrived.
private final class ClockSample: @unchecked Sendable {
    struct Reading {
        let frame: Double
        let uptime: Double
        let continuous: Double
    }

    private let lock = NSLock()
    private var sample: Reading?

    func record(_ frame: Double) {
        let uptime = ProcessInfo.processInfo.systemUptime
        // A monotonic clock that keeps counting while the system sleeps.
        let continuous = Double(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1e9
        lock.lock()
        defer { lock.unlock() }
        if sample == nil {
            sample = Reading(frame: frame, uptime: uptime, continuous: continuous)
        }
    }

    var value: Reading? {
        lock.lock()
        defer { lock.unlock() }
        return sample
    }
}

/// Compares the frame clock with the system uptime, waiting up to `seconds` for a first frame.
private func compareClocks(waiting seconds: Double) {
    let sample = ClockSample()
    let stream = RawFrameStream(devices: MultitouchDevices.enumerate())
    stream.onFrame = { _, _, timestamp in sample.record(timestamp) }
    startStream(stream)
    output("touch the trackpad once to compare clocks (\(seconds) s)...")
    pumpRunLoop(until: Date().addingTimeInterval(seconds)) { sample.value != nil }
    stream.stop()
    guard let value = sample.value else {
        output(String(format: "clock: no frame; uptime now %.4f", ProcessInfo.processInfo.systemUptime))
        return
    }
    output(String(
        format: "clock: frame timestamp %.4f, system uptime %.4f (difference %.4f s), "
            + "uptime including sleep %.4f (difference %.4f s)",
        value.frame, value.uptime, value.uptime - value.frame, value.continuous, value.continuous - value.frame
    ))
}

func runPipeline(_ options: [String]) {
    var seconds = 20.0
    if let value = options.first {
        guard let parsed = Double(value), parsed > 0 else { usageError("invalid seconds: \(value)") }
        seconds = parsed
    }
    compareClocks(waiting: min(3, seconds))

    let config = EngineConfig()
    let sink = LoggingSink()
    let engine = GestureEngine(config: config, sink: sink)
    let pipeline = GesturePipeline(engine: engine, lostTimeout: config.thresholds.lostTimeout)
    do {
        try pipeline.start()
    } catch {
        output("cannot start pipeline: \(error)")
        exit(1)
    }
    output("pipeline running on \(pipeline.deviceCount) device(s) for \(seconds) s; commands are printed, not sent")
    pumpRunLoop(until: Date().addingTimeInterval(seconds))
    pipeline.stop()
    withExtendedLifetime(sink) {}
    output("pipeline stopped")
}

// MARK: - mem

func runMem() {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else {
        output("task_info failed: \(result)")
        exit(1)
    }
    output(String(format: "phys_footprint: %.1f MB", Double(info.phys_footprint) / 1_048_576))
}
