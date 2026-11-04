import CMultitouch
import Foundation
import Testing
import TrrekEngine
@testable import TrrekPlatform

// Synthetic device handles; never dereferenced. A is an external trackpad, B the built-in one.

private var refA: MTDeviceRef {
    UnsafeMutableRawPointer(bitPattern: 0xA100)!
}

private var refB: MTDeviceRef {
    UnsafeMutableRawPointer(bitPattern: 0xB100)!
}

private var externalA: MultitouchDeviceInfo {
    MultitouchDeviceInfo(
        ref: refA, isBuiltIn: false, widthMM: 160, heightMM: 115, multitouchID: 11, kind: .trackpad
    )
}

private var builtInB: MultitouchDeviceInfo {
    MultitouchDeviceInfo(
        ref: refB, isBuiltIn: true, widthMM: 121.94, heightMM: 74.08, multitouchID: 22, kind: .trackpad
    )
}

/// Actuators for multitouch IDs 11 (A) and 22 (B), plus the system fallback.
private struct HapticsRig {
    let actuatorA = FakeActuator()
    let actuatorB = FakeActuator()
    let fallback = FakeActuator()
    let haptics: DeviceHaptics

    init(devices: [MultitouchDeviceInfo] = [externalA, builtInB]) {
        haptics = DeviceHaptics(fallback: fallback)
        install(devices)
    }

    func install(_ devices: [MultitouchDeviceInfo]) {
        let actuators = [UInt64(11): actuatorA, 22: actuatorB]
        haptics.install(devices: devices) { actuators[$0] }
    }

    func dispatcher() -> CommandDispatcher {
        CommandDispatcher(
            mediaKeys: FakeMediaKeys(),
            keys: FakeKeys(),
            mouse: FakeMouse(),
            haptics: haptics,
            freezer: FakeFreezer(),
            backlight: nil,
            overlay: nil
        )
    }
}

@Test func hapticPlaysOnTheDeviceOfTheCommand() {
    let rig = HapticsRig()
    let dispatcher = rig.dispatcher()
    dispatcher.handle(.haptic(.start), device: GesturePipeline.deviceID(of: refA))
    dispatcher.handle(.haptic(.step), device: GesturePipeline.deviceID(of: refA))
    #expect(rig.actuatorA.events == [.start, .step])
    #expect(rig.actuatorB.events.isEmpty)

    dispatcher.handle(.haptic(.tap), device: GesturePipeline.deviceID(of: refB))
    #expect(rig.actuatorB.events == [.tap])
    #expect(rig.fallback.events.isEmpty)
}

@Test func unknownDeviceFallsBackToTheBuiltInActuator() {
    let rig = HapticsRig()
    rig.haptics.perform(.start, strength: .medium, device: 0xDEAD)
    #expect(rig.actuatorB.events == [.start])
    #expect(rig.actuatorA.events.isEmpty)
    #expect(rig.fallback.events.isEmpty)
}

@Test func withoutActuatorsTheFallbackPlays() {
    // Neither device has a multitouch ID: no actuator can be opened.
    let noID = MultitouchDeviceInfo(ref: refA, isBuiltIn: true, widthMM: 100, heightMM: 70, multitouchID: nil)
    let rig = HapticsRig(devices: [noID])
    #expect(rig.haptics.actuatorCount == 0)
    rig.haptics.perform(.step, strength: .light, device: GesturePipeline.deviceID(of: refA))
    #expect(rig.fallback.events == [.step])
}

@Test func reinstallReplacesTheActuators() {
    let rig = HapticsRig()
    #expect(rig.haptics.actuatorCount == 2)
    // Trackpad A was unplugged and the pipeline restarted with B alone.
    rig.install([builtInB])
    #expect(rig.haptics.actuatorCount == 1)
    rig.haptics.perform(.start, strength: .medium, device: GesturePipeline.deviceID(of: refA))
    #expect(rig.actuatorA.events.isEmpty)
    #expect(rig.actuatorB.events == [.start])
}

@Test func limitHapticPlaysOnTheSlidingDevice() {
    let rig = HapticsRig()
    let backlight = FakeBacklight(level: 1)
    let dispatcher = CommandDispatcher(
        mediaKeys: FakeMediaKeys(),
        keys: FakeKeys(),
        mouse: FakeMouse(),
        haptics: rig.haptics,
        freezer: FakeFreezer(),
        backlight: backlight,
        overlay: nil
    )
    let device = GesturePipeline.deviceID(of: refA)
    dispatcher.handle(.haptic(.start), device: device)
    dispatcher.handle(.stepKeyboardBacklight(1, fine: false), device: device)
    #expect(rig.actuatorA.events == [.start, .limit])
    #expect(rig.actuatorB.events.isEmpty)
}

@Test func slideOnAnExternalTrackpadPlaysOnItsActuator() {
    let rig = HapticsRig()
    let dispatcher = rig.dispatcher()
    let engine = GestureEngine(config: EngineConfig(), sink: dispatcher)
    let pipeline = GesturePipeline(engine: engine)
    _ = pipeline.install(devices: [externalA, builtInB])
    let base = GesturePipeline.uptime()
    // Slide up the right edge of device A.
    for (step, y) in [Float(0.30), 0.32, 0.34, 0.36, 0.40].enumerated() {
        let offset = Double(step) * 0.008
        [contact(id: 1, state: 4, nx: 0.98, ny: y)].withUnsafeBufferPointer {
            pipeline.handleFrame(refA, $0, 1000 + offset, uptime: base + offset)
        }
    }
    #expect(pipeline.withEngine(\.stateKind) == .sliding)
    #expect(rig.actuatorA.events.first == .start)
    #expect(rig.actuatorA.events.contains(.step))
    #expect(rig.actuatorB.events.isEmpty)
    #expect(rig.fallback.events.isEmpty)
    pipeline.stop()
}
