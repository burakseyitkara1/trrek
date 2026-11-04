import CMultitouch
import Foundation
import Testing
import TrrekEngine
@testable import TrrekPlatform

// Synthetic device handles; never dereferenced.

private var deviceA: MTDeviceRef {
    UnsafeMutableRawPointer(bitPattern: 0xA000)!
}

private var deviceB: MTDeviceRef {
    UnsafeMutableRawPointer(bitPattern: 0xB000)!
}

private func device(_ ref: MTDeviceRef) -> MultitouchDeviceInfo {
    MultitouchDeviceInfo(ref: ref, isBuiltIn: true, widthMM: 121.94, heightMM: 74.08, multitouchID: nil)
}

/// A config whose long lost timeout keeps the watchdog from firing during a test.
private func patientConfig(lostTimeout: TimeInterval = 60) -> EngineConfig {
    var config = EngineConfig()
    config.thresholds.lostTimeout = lostTimeout
    return config
}

/// A pipeline with synthetic devices. The long watchdog timeout keeps the timer from firing during a test.
private func makePipeline(
    _ refs: [MTDeviceRef],
    config: EngineConfig = patientConfig(),
    clock: @escaping @Sendable () -> TimeInterval = GesturePipeline.uptime
) -> (GesturePipeline, CollectingSink) {
    let sink = CollectingSink()
    let engine = GestureEngine(config: config, sink: sink)
    let pipeline = GesturePipeline(engine: engine, clock: clock)
    _ = pipeline.install(devices: refs.map(device))
    return (pipeline, sink)
}

private func feed(
    _ pipeline: GesturePipeline,
    _ ref: MTDeviceRef,
    _ contacts: [MTTouch],
    timestamp: Double,
    uptime: Double
) {
    contacts.withUnsafeBufferPointer {
        pipeline.handleFrame(ref, $0, timestamp, uptime: uptime)
    }
}

private func isClose(_ value: TimeInterval?, _ expected: TimeInterval) -> Bool {
    guard let value else { return false }
    return abs(value - expected) < 1e-6
}

@Test func engineTimeIsNilBeforeAnyFrame() {
    let (pipeline, _) = makePipeline([deviceA])
    #expect(pipeline.engineTime(fromUptime: GesturePipeline.uptime()) == nil)
}

@Test func engineTimeMapsUptimeToFrameClock() {
    let (pipeline, _) = makePipeline([deviceA])
    let base = GesturePipeline.uptime()
    feed(pipeline, deviceA, [], timestamp: 500, uptime: base)
    #expect(isClose(pipeline.engineTime(fromUptime: base + 1), 501))
    #expect(isClose(pipeline.engineTime(fromUptime: base), 500))
}

@Test func framesFromUnknownDevicesAreIgnored() {
    let (pipeline, _) = makePipeline([deviceA])
    feed(pipeline, deviceB, [], timestamp: 500, uptime: GesturePipeline.uptime())
    #expect(pipeline.engineTime(fromUptime: GesturePipeline.uptime()) == nil)
}

@Test func engineTimeFollowsTheSlidingDevice() {
    let (pipeline, sink) = makePipeline([deviceA, deviceB])
    let base = GesturePipeline.uptime()
    // Slide up the right edge of device A, whose clock reads 1000 at `base`.
    for (step, y) in [Float(0.30), 0.32, 0.34, 0.36, 0.40].enumerated() {
        let offset = Double(step) * 0.008
        feed(
            pipeline,
            deviceA,
            [contact(id: 1, state: 4, nx: 0.98, ny: y)],
            timestamp: 1000 + offset,
            uptime: base + offset
        )
    }
    #expect(pipeline.withEngine(\.stateKind) == .sliding)
    #expect(sink.commands.contains(.stepVolume(1, fine: false)))

    // Device B runs on a clock far ahead; its frames must not move the engine's clock during the slide.
    feed(pipeline, deviceB, [], timestamp: 9000, uptime: base + 0.04)
    #expect(isClose(pipeline.engineTime(fromUptime: base + 1), 1001))

    // Once idle, the most recent device's clock applies.
    pipeline.withEngine { $0.reset() }
    #expect(isClose(pipeline.engineTime(fromUptime: base + 1), 9000.96))
}

@Test func onlyTrackpadsAreInstalled() {
    let sink = CollectingSink()
    let pipeline = GesturePipeline(engine: GestureEngine(config: patientConfig(), sink: sink))
    let geometry = (width: Float(121.94), height: Float(74.08))
    let mouse = MultitouchDeviceInfo(
        ref: deviceB, isBuiltIn: false, widthMM: geometry.width, heightMM: geometry.height,
        multitouchID: 2, kind: .other
    )
    let trackpad = MultitouchDeviceInfo(
        ref: deviceA, isBuiltIn: true, widthMM: geometry.width, heightMM: geometry.height,
        multitouchID: 1, kind: .trackpad
    )
    let selected = pipeline.install(devices: [mouse, trackpad])
    #expect(selected.map(\.ref) == [deviceA])
    #expect(pipeline.deviceCount == 1)

    // A pipeline with only a non-trackpad has no device: start would report `noDevices`.
    #expect(pipeline.install(devices: [mouse]).isEmpty)
    #expect(pipeline.deviceCount == 0)
}

/// Records the issues a pipeline reports; written and read on the main thread.
private final class IssueRecorder: @unchecked Sendable {
    var issues: [PipelineIssue] = []
}

/// Lets the main queue run until `done` holds or a few seconds pass.
@MainActor
private func waitForMain(_ done: () -> Bool) async throws {
    let deadline = Date(timeIntervalSinceNow: 5)
    while !done(), Date() < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
@Test(arguments: [
    contact(id: 1, state: 4, nx: .nan, ny: 0.5),
    contact(id: 1, state: 4, nx: 0.5, ny: 1.2),
    contact(id: 1, state: 4, nx: -0.1, ny: 0.5),
    contact(id: 1, state: 4, nx: 0.5, ny: 0.5, majorAxis: 150),
    contact(id: 1, state: 4, nx: 0.5, ny: 0.5, majorAxis: -1),
    contact(id: 1, state: 4, nx: 0.5, ny: 0.5, majorAxis: .infinity)
])
func implausibleFirstFrameStopsThePipeline(_ bad: MTTouch) async throws {
    let (pipeline, sink) = makePipeline([deviceA])
    let recorder = IssueRecorder()
    pipeline.onDataUnavailable = { recorder.issues.append($0) }
    let base = GesturePipeline.uptime()
    // An empty frame is not checked; the first frame with a contact is.
    feed(pipeline, deviceA, [], timestamp: 100, uptime: base)
    feed(pipeline, deviceA, [contact(id: 2, state: 4, nx: 0.98, ny: 0.3), bad], timestamp: 100.01, uptime: base)
    // Frames after the rejected one are dropped before the main thread stops the pipeline.
    feed(pipeline, deviceA, [contact(id: 2, state: 4, nx: 0.98, ny: 0.4)], timestamp: 100.02, uptime: base)
    #expect(pipeline.deviceCount == 0)

    try await waitForMain { !recorder.issues.isEmpty }
    #expect(recorder.issues == [.dataUnavailable])
    #expect(!pipeline.isRunning)
    #expect(sink.commands.isEmpty)
}

@MainActor
@Test(arguments: [Int32(8), -3])
func unknownContactStateFailsTheFirstFrame(_ state: Int32) async throws {
    let (pipeline, sink) = makePipeline([deviceA])
    let recorder = IssueRecorder()
    pipeline.onDataUnavailable = { recorder.issues.append($0) }
    let base = GesturePipeline.uptime()
    // With a drifted layout no contact may read as touching; the unknown state alone fails the check.
    feed(pipeline, deviceA, [contact(id: 1, state: state, nx: 0.5, ny: 0.5)], timestamp: 100, uptime: base)
    try await waitForMain { !recorder.issues.isEmpty }
    #expect(recorder.issues == [.dataUnavailable])
    #expect(!pipeline.isRunning)
    #expect(sink.commands.isEmpty)
}

@MainActor
@Test func onlyTheFirstFrameIsChecked() async throws {
    let (pipeline, _) = makePipeline([deviceA])
    let recorder = IssueRecorder()
    pipeline.onDataUnavailable = { recorder.issues.append($0) }
    let base = GesturePipeline.uptime()
    feed(pipeline, deviceA, [contact(id: 1, state: 4, nx: 0.5, ny: 0.5)], timestamp: 100, uptime: base)
    // Later frames go straight to the engine, which has its own guards.
    feed(pipeline, deviceA, [contact(id: 1, state: 4, nx: 2, ny: 0.5)], timestamp: 100.01, uptime: base)
    try await Task.sleep(for: .milliseconds(50))
    #expect(recorder.issues.isEmpty)
    #expect(pipeline.deviceCount == 1)
}

@MainActor
@Test func firstFrameCheckIgnoresContactsThatAreNotTouching() async throws {
    let (pipeline, _) = makePipeline([deviceA])
    let recorder = IssueRecorder()
    pipeline.onDataUnavailable = { recorder.issues.append($0) }
    let base = GesturePipeline.uptime()
    // A hovering or lifting contact may carry out-of-range values; it neither fails nor uses up the check.
    feed(pipeline, deviceA, [contact(id: 1, state: 1, nx: 3, ny: 0.5)], timestamp: 100, uptime: base)
    feed(pipeline, deviceA, [
        contact(id: 2, state: 4, nx: 0.5, ny: 0.5),
        contact(id: 3, state: 5, nx: 0.5, ny: 0.5, majorAxis: 500)
    ], timestamp: 100.01, uptime: base)
    try await Task.sleep(for: .milliseconds(50))
    #expect(recorder.issues.isEmpty)
    #expect(pipeline.deviceCount == 1)
}

@MainActor
@Test func firstTouchingFrameIsCheckedAfterNonTouchingOnes() async throws {
    let (pipeline, _) = makePipeline([deviceA])
    let recorder = IssueRecorder()
    pipeline.onDataUnavailable = { recorder.issues.append($0) }
    let base = GesturePipeline.uptime()
    feed(pipeline, deviceA, [contact(id: 1, state: 1)], timestamp: 100, uptime: base)
    feed(pipeline, deviceA, [contact(id: 1, state: 3, nx: 1.5, ny: 0.5)], timestamp: 100.01, uptime: base)
    try await waitForMain { !recorder.issues.isEmpty }
    #expect(recorder.issues == [.dataUnavailable])
}

// MARK: - Watchdog

/// A clock the test sets; the pipeline reads it as system uptime.
private final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval

    init(_ value: TimeInterval) {
        self.value = value
    }

    func read() -> TimeInterval {
        lock.withLock { value }
    }

    func set(_ newValue: TimeInterval) {
        lock.withLock { value = newValue }
    }
}

/// Slides up the right edge of `ref`, whose frame clock reads `timestamp` at uptime `uptime`; returns the uptime of
/// the last frame.
@discardableResult
private func slide(_ pipeline: GesturePipeline, _ ref: MTDeviceRef, timestamp: Double, uptime: Double) -> Double {
    var last = uptime
    for (step, y) in [Float(0.30), 0.32, 0.34, 0.36, 0.40].enumerated() {
        let offset = Double(step) * 0.008
        last = uptime + offset
        feed(pipeline, ref, [contact(id: 1, state: 4, nx: 0.98, ny: y)], timestamp: timestamp + offset, uptime: last)
    }
    return last
}

@Test func watchdogTicksWithTheSlidingDevicesClock() {
    let clock = ManualClock(50)
    let (pipeline, sink) = makePipeline([deviceA, deviceB], config: patientConfig(lostTimeout: 0.2), clock: clock.read)
    let lastA = slide(pipeline, deviceA, timestamp: 1000, uptime: 50)
    #expect(pipeline.withEngine(\.stateKind) == .sliding)
    // Device B runs on a clock far ahead; ticking with it would end the slide at once.
    feed(pipeline, deviceB, [], timestamp: 9000, uptime: lastA + 0.01)

    // Before the timeout in device A's clock the slide goes on.
    clock.set(lastA + 0.1)
    pipeline.watchdogFired()
    #expect(pipeline.withEngine(\.stateKind) == .sliding)

    // Past it, the tick commits the slide.
    clock.set(lastA + 0.25)
    pipeline.watchdogFired()
    #expect(pipeline.withEngine(\.stateKind) == .idle)
    #expect(sink.commands.contains(.stepVolume(1, fine: false)))
}

@Test func watchdogFollowsLostTimeoutUpdates() async throws {
    // Built with a timeout far longer than the test; the update shortens it before the slide starts.
    let (pipeline, _) = makePipeline([deviceA])
    pipeline.withEngine { $0.update(config: patientConfig(lostTimeout: 0.1)) }
    slide(pipeline, deviceA, timestamp: 1000, uptime: GesturePipeline.uptime())
    #expect(pipeline.withEngine(\.stateKind) == .sliding)

    let deadline = Date(timeIntervalSinceNow: 3)
    while pipeline.withEngine(\.stateKind) != .idle, Date() < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(pipeline.withEngine(\.stateKind) == .idle)
}
