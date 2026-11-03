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

/// A pipeline with synthetic devices. The long watchdog timeout keeps the timer from firing during a test.
private func makePipeline(_ refs: [MTDeviceRef]) -> (GesturePipeline, CollectingSink) {
    let sink = CollectingSink()
    let engine = GestureEngine(config: EngineConfig(), sink: sink)
    let pipeline = GesturePipeline(engine: engine, lostTimeout: 60)
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
