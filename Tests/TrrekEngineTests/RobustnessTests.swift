import Foundation
import Testing
@testable import TrrekEngine

// Input guards, the bottom-quarter corner rule, commit and cancel paths outside a moving slide, and locking.

// swiftlint:disable:next large_tuple
private func makeEngine(_ config: EngineConfig = EngineConfig()) -> (GestureEngine, RecordingSink, FrameBuilder) {
    let sink = RecordingSink()
    let engine = GestureEngine(config: config, sink: sink)
    return (engine, sink, FrameBuilder())
}

private func stepCount(_ sink: RecordingSink) -> Int {
    sink.commands.filter {
        switch $0 {
        case .stepVolume, .stepBrightness, .stepKeyboardBacklight, .appSwitchStep, .scrubStep, .mediaNext,
             .mediaPrevious:
            true
        default:
            false
        }
    }.count
}

// MARK: - Input guards

/// A frame on the builder's device with one touch at normalized (`x`, `y`), bypassing the mm conversion.
private func rawFrame(_ fb: FrameBuilder, t: TimeInterval, id: Int32, x: Float, y: Float) -> Frame {
    var touches = TouchBuffer()
    touches.append(Touch(id: id, x: x, y: y, majorAxisMM: 8))
    return Frame(deviceID: fb.deviceID, timestamp: t, geometry: fb.geometry, touches: touches)
}

@Test func nonFiniteCoordinateCancelsSlide() {
    let (e, sink, fb) = makeEngine()
    var t = e.drive(fb, id: 1, from: (30, 78), to: (54, 78), startT: 0)
    #expect(sink.count(.appSwitchStep(1)) == 2)
    let steps = stepCount(sink)
    t += 0.008
    e.process(rawFrame(fb, t: t, id: 1, x: .infinity, y: 78 / 80))
    #expect(e.stateKind == .spent)
    #expect(sink.count(.appSwitchCancel) == 1)
    #expect(sink.contains(.appSwitchCommit) == false)
    #expect(sink.count(.freezeCursor(false)) == 1)
    #expect(sink.commands.last == .freezeCursor(false))
    #expect(stepCount(sink) == steps)
    t += 0.008
    e.process(rawFrame(fb, t: t, id: 1, x: .nan, y: 78 / 80))
    #expect(e.stateKind == .spent)
    #expect(stepCount(sink) == steps)
    e.process(fb.frame(t: t + 0.008, []))
    #expect(e.stateKind == .idle)
    #expect(sink.count(.freezeCursor(false)) == 1)
}

@Test func hugeCoordinateIsCapped() {
    let (e, sink, fb) = makeEngine()
    var t = e.drive(fb, id: 1, from: (115, 15), to: (115, 35), startT: 0)
    var before = stepCount(sink)
    #expect(before == 5)
    t += 0.008
    e.process(rawFrame(fb, t: t, id: 1, x: 115 / 120, y: 1e9))
    let inFrame = stepCount(sink) - before
    #expect(inFrame > 0)
    #expect(inFrame <= 64)
    #expect(sink.count(.haptic(.step)) == stepCount(sink))
    #expect(e.stateKind == .sliding)

    // The rest of the garbage distance is dropped: the same coordinate again emits nothing.
    before = stepCount(sink)
    t += 0.008
    e.process(rawFrame(fb, t: t, id: 1, x: 115 / 120, y: 1e9))
    #expect(stepCount(sink) == before)
    #expect(e.stateKind == .sliding)

    // The finger drops out and comes back on the pad; a normal 3.75 mm move is exactly one step.
    t += 0.008
    e.process(fb.frame(t: t, []))
    #expect(e.stateKind == .lost)
    t += 0.008
    e.process(fb.frame(t: t, [(1, 115, 40)]))
    #expect(e.stateKind == .sliding)
    #expect(stepCount(sink) == before)
    t += 0.008
    e.process(fb.frame(t: t, [(1, 115, 43.75)]))
    #expect(stepCount(sink) == before + 1)
}

// MARK: - Bottom quarter only

@Test func bottomQuarterOnlyBlocksVerticalSlideFromTopCorner() {
    var cfg = EngineConfig()
    cfg.bottomQuarterOnly = true
    let (e, sink, fb) = makeEngine(cfg)
    e.process(fb.frame(t: 0, [(1, 115, 75)]))
    #expect(e.stateKind == .candidate)
    let t = e.drive(fb, id: 1, from: (115, 75), to: (115, 40), startT: 0.008)
    #expect(e.stateKind == .spent)
    #expect(sink.commands.isEmpty)
    e.process(fb.frame(t: t + 0.008, []))
    #expect(e.stateKind == .idle)
    #expect(sink.commands.isEmpty)
}

@Test func bottomQuarterOnlyAllowsHorizontalSlideFromTopCorner() {
    var cfg = EngineConfig()
    cfg.bottomQuarterOnly = true
    let (e, sink, fb) = makeEngine(cfg)
    e.drive(fb, id: 1, from: (115, 75), to: (90, 75), startT: 0)
    #expect(e.stateKind == .sliding)
    #expect(sink.count(.appSwitchStep(-1)) == 2)
    #expect(sink.count(.appSwitchStep(1)) == 0)
}

// MARK: - Commit paths while the finger is lost

/// Starts an app-switch slide on the top edge and lifts the finger, leaving the engine in `lost`.
private func lostAppSwitch(_ e: GestureEngine, _ sink: RecordingSink, _ fb: FrameBuilder) {
    let t = e.drive(fb, id: 1, from: (30, 78), to: (54, 78), startT: 0)
    #expect(sink.count(.appSwitchStep(1)) == 2)
    e.process(fb.frame(t: t + 0.008, []))
    #expect(e.stateKind == .lost)
}

@Test func updateConfigDuringLostCommits() {
    let (e, sink, fb) = makeEngine()
    lostAppSwitch(e, sink, fb)
    e.update(config: EngineConfig())
    #expect(e.stateKind == .idle)
    #expect(sink.count(.appSwitchCommit) == 1)
    #expect(sink.contains(.appSwitchCancel) == false)
    #expect(sink.count(.freezeCursor(false)) == 1)
}

@Test func updateConfigDropsCandidate() {
    let (e, sink, fb) = makeEngine()
    e.process(fb.frame(t: 0, [(1, 115, 15)]))
    #expect(e.stateKind == .candidate)
    var cfg = EngineConfig()
    cfg.precision = true
    e.update(config: cfg)
    #expect(e.stateKind == .spent)
    let t = e.drive(fb, id: 1, from: (115, 15), to: (115, 75), startT: 0.008)
    #expect(e.stateKind == .spent)
    #expect(sink.commands.isEmpty)
    e.process(fb.frame(t: t + 0.008, []))
    #expect(e.stateKind == .idle)
    #expect(sink.commands.isEmpty)
}

@Test func otherDeviceIgnoredWhileCandidateAndSpent() {
    let (e, sink, fb) = makeEngine()
    var other = FrameBuilder()
    other.deviceID = 2
    e.process(fb.frame(t: 0, [(1, 115, 15)]))
    #expect(e.stateKind == .candidate)
    e.process(other.frame(t: 0.008, []))
    #expect(e.stateKind == .candidate)
    e.process(other.frame(t: 0.016, [(1, 115, 60), (2, 60, 40)]))
    #expect(e.stateKind == .candidate)
    #expect(sink.commands.isEmpty)

    // Abort the candidate with a perpendicular move, then the other device again.
    e.process(fb.frame(t: 0.024, [(1, 110, 15)]))
    #expect(e.stateKind == .spent)
    e.process(other.frame(t: 0.032, []))
    #expect(e.stateKind == .spent)
    e.process(other.frame(t: 0.04, [(5, 115, 15)]))
    #expect(e.stateKind == .spent)
    e.process(fb.frame(t: 0.048, []))
    #expect(e.stateKind == .idle)
    #expect(sink.commands.isEmpty)
}

@Test func resetDuringScrubCancels() {
    var cfg = EngineConfig()
    cfg.top = .scrubVideo
    let (e, sink, fb) = makeEngine(cfg)
    e.drive(fb, id: 1, from: (30, 78), to: (42, 78), startT: 0)
    #expect(sink.count(.scrubStep(1)) == 2)
    e.reset()
    #expect(e.stateKind == .idle)
    #expect(sink.count(.scrubCancel) == 1)
    #expect(sink.contains(.scrubCommit) == false)
    #expect(sink.count(.freezeCursor(false)) == 1)
}

// MARK: - Locking

@Test func concurrentCallsKeepCursorFreezeBalanced() {
    let (e, sink, fb) = makeEngine()
    DispatchQueue.concurrentPerform(iterations: 8) { worker in
        let id = Int32(worker + 1)
        for round in 0 ..< 20 {
            let t = Double(round) + Double(worker) * 0.001
            e.drive(fb, id: id, from: (115, 15), to: (115, 35), startT: t)
            e.tick(now: t + 0.05)
            if round.isMultiple(of: 3) {
                e.reset()
            }
            e.noteKeyDown(at: -1)
            e.setHoldKeySatisfied(true)
            e.process(fb.frame(t: t + 0.5, []))
        }
    }
    e.reset()
    #expect(e.stateKind == .idle)
    #expect(sink.count(.freezeCursor(true)) == sink.count(.freezeCursor(false)))
}
