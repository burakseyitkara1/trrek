import Foundation
import Testing
@testable import TrrekEngine

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

private func holdKeyConfig() -> EngineConfig {
    var cfg = EngineConfig()
    cfg.holdKeyRequired = true
    return cfg
}

/// A frame with one finger plus a resting palm (major axis 30 mm) in the middle of the pad.
private func frameWithPalm(_ fb: FrameBuilder, t: TimeInterval, finger: (Float, Float)) -> Frame {
    var frame = fb.frame(t: t, [(1, finger.0, finger.1)])
    frame.touches.append(Touch(id: 2, x: 0.5, y: 0.5, majorAxisMM: 30))
    return frame
}

// MARK: - Palm filter

@Test func palmTouchIsFiltered() {
    let (e, sink, fb) = makeEngine()
    let t = e.drive(fb, id: 1, from: (115, 15), to: (115, 75), major: 21, startT: 0)
    #expect(e.stateKind == .idle)
    #expect(sink.commands.isEmpty)
    e.process(fb.frame(t: t + 0.008, []))
    e.drive(fb, id: 2, from: (115, 15), to: (115, 75), major: 19, startT: t + 0.1)
    #expect(e.stateKind == .sliding)
    #expect(sink.count(.stepVolume(1, fine: false)) == 16)
}

@Test func palmAlongsideFingerDoesNotCancelSlide() {
    let (e, sink, fb) = makeEngine()
    var t = e.drive(fb, id: 1, from: (115, 15), to: (115, 35), startT: 0)
    #expect(stepCount(sink) == 5)
    for yMM in stride(from: Float(36), through: 75, by: 1) {
        t += 0.008
        e.process(frameWithPalm(fb, t: t, finger: (115, yMM)))
        #expect(e.stateKind == .sliding)
    }
    #expect(sink.count(.stepVolume(1, fine: false)) == 16)
    #expect(sink.count(.freezeCursor(false)) == 0)
    #expect(sink.contains(.appSwitchCancel) == false)
    // A palm alone does not keep the slide alive: the finger is gone, so the slide is lost.
    e.process(frameWithPalm(fb, t: t + 0.008, finger: (115, 75)).withoutFinger(1))
    #expect(e.stateKind == .lost)
}

// MARK: - Typing gate

@Test func typingGateBlocksNewGesture() {
    let (e, sink, fb) = makeEngine()
    e.noteKeyDown(at: 0)
    let t = e.drive(fb, id: 1, from: (115, 15), to: (115, 35), startT: 0.1)
    #expect(e.stateKind == .spent)
    #expect(sink.commands.isEmpty)
    e.process(fb.frame(t: t + 0.008, []))
    #expect(e.stateKind == .idle)
    e.drive(fb, id: 2, from: (115, 15), to: (115, 75), startT: 0.5)
    #expect(e.stateKind == .sliding)
    #expect(sink.count(.stepVolume(1, fine: false)) == 16)

    // A finger already resting as a candidate does not start a slide once a key goes down.
    let (e2, sink2, _) = makeEngine()
    e2.process(fb.frame(t: 0, [(1, 115, 15)]))
    #expect(e2.stateKind == .candidate)
    e2.noteKeyDown(at: 0.01)
    e2.drive(fb, id: 1, from: (115, 15), to: (115, 75), startT: 0.02)
    #expect(e2.stateKind == .spent)
    #expect(sink2.commands.isEmpty)
}

@Test func typingDoesNotStopActiveSlide() {
    let (e, sink, fb) = makeEngine()
    let t = e.drive(fb, id: 1, from: (115, 15), to: (115, 35), startT: 0)
    #expect(stepCount(sink) == 5)
    e.noteKeyDown(at: t)
    #expect(e.stateKind == .sliding)
    #expect(stepCount(sink) == 5)
    e.drive(fb, id: 1, from: (115, 35), to: (115, 75), startT: t + 0.008)
    #expect(e.stateKind == .sliding)
    #expect(sink.count(.stepVolume(1, fine: false)) == 16)
    #expect(sink.count(.freezeCursor(false)) == 0)
}

// MARK: - Hold-to-Slide

@Test func holdKeyRequiredBlocksWithoutKey() {
    let (e, sink, fb) = makeEngine(holdKeyConfig())
    let t = e.drive(fb, id: 1, from: (115, 15), to: (115, 75), startT: 0)
    #expect(e.stateKind == .spent)
    #expect(sink.commands.isEmpty)
    e.process(fb.frame(t: t + 0.008, []))
    #expect(e.stateKind == .idle)
    e.setHoldKeySatisfied(true)
    #expect(e.stateKind == .idle)
    #expect(sink.commands.isEmpty)
    e.drive(fb, id: 2, from: (115, 15), to: (115, 75), startT: t + 0.1)
    #expect(e.stateKind == .sliding)
    #expect(sink.count(.stepVolume(1, fine: false)) == 16)
}

@Test func releasingHoldKeyCommitsSlide() {
    let (e, sink, fb) = makeEngine(holdKeyConfig())
    e.setHoldKeySatisfied(true)
    let t = e.drive(fb, id: 1, from: (115, 15), to: (115, 35), startT: 0)
    #expect(e.stateKind == .sliding)
    let steps = stepCount(sink)
    e.setHoldKeySatisfied(false)
    #expect(e.stateKind == .idle)
    #expect(sink.count(.freezeCursor(false)) == 1)
    #expect(sink.count(.freezeCursor(true)) == 1)
    // The finger keeps moving, but without the key it cannot start another gesture.
    e.drive(fb, id: 1, from: (115, 36), to: (115, 75), startT: t + 0.008)
    #expect(e.stateKind == .spent)
    #expect(stepCount(sink) == steps)
    #expect(sink.count(.freezeCursor(false)) == 1)
}

@Test func releasingHoldKeyDropsCandidateAndMiddleClick() {
    var cfg = holdKeyConfig()
    cfg.middleClickEnabled = true
    let (e, sink, fb) = makeEngine(cfg)
    e.setHoldKeySatisfied(true)
    e.process(fb.frame(t: 0, [(1, 115, 15)]))
    #expect(e.stateKind == .candidate)
    e.setHoldKeySatisfied(false)
    #expect(e.stateKind == .spent)
    e.process(fb.frame(t: 0.05, []))
    #expect(e.stateKind == .idle)

    e.setHoldKeySatisfied(true)
    e.process(fb.frame(t: 1, [(1, 40, 40), (2, 60, 40), (3, 80, 40)]))
    #expect(e.stateKind == .threeFinger)
    e.setHoldKeySatisfied(false)
    #expect(e.stateKind == .spent)
    e.process(fb.frame(t: 1.05, []))
    #expect(e.stateKind == .idle)
    #expect(sink.commands.isEmpty)
}

@Test func releasingHoldKeyCommitsSwitchApps() {
    let (e, sink, fb) = makeEngine(holdKeyConfig())
    e.setHoldKeySatisfied(true)
    e.drive(fb, id: 1, from: (30, 78), to: (54, 78), startT: 0)
    #expect(sink.count(.appSwitchStep(1)) == 2)
    e.setHoldKeySatisfied(false)
    #expect(e.stateKind == .idle)
    #expect(sink.count(.appSwitchCommit) == 1)
    #expect(sink.count(.appSwitchCancel) == 0)
    #expect(sink.count(.freezeCursor(false)) == 1)
}

@Test func holdKeyReleaseDuringLostCommits() {
    let (e, sink, fb) = makeEngine(holdKeyConfig())
    e.setHoldKeySatisfied(true)
    let t = e.drive(fb, id: 1, from: (30, 78), to: (54, 78), startT: 0)
    e.process(fb.frame(t: t + 0.008, []))
    #expect(e.stateKind == .lost)
    e.setHoldKeySatisfied(false)
    #expect(e.stateKind == .idle)
    #expect(sink.count(.appSwitchCommit) == 1)
    #expect(sink.count(.appSwitchCancel) == 0)
    #expect(sink.count(.freezeCursor(false)) == 1)
    // The watchdog finds nothing left to end.
    e.tick(now: t + 1)
    #expect(sink.count(.appSwitchCommit) == 1)
}

// MARK: - Pause

@Test func pausedIgnoresFrames() {
    var cfg = EngineConfig()
    cfg.topRight = .mute
    cfg.middleClickEnabled = true
    let (e, sink, fb) = makeEngine(cfg)
    e.setPaused(true)
    var t = e.drive(fb, id: 1, from: (115, 15), to: (115, 75), startT: 0)
    #expect(e.stateKind == .idle)
    // Corner double-tap and three-finger tap are ignored as well.
    for _ in 0 ..< 2 {
        t += 0.05
        e.process(fb.frame(t: t, [(3, 118, 78)]))
        t += 0.05
        e.process(fb.frame(t: t, []))
    }
    t += 0.05
    e.process(fb.frame(t: t, [(4, 40, 40), (5, 60, 40), (6, 80, 40)]))
    #expect(e.stateKind == .idle)
    t += 0.05
    e.process(fb.frame(t: t, []))
    e.tick(now: t + 1)
    #expect(sink.commands.isEmpty)
    #expect(e.stateKind == .idle)

    e.setPaused(false)
    e.drive(fb, id: 7, from: (115, 15), to: (115, 75), startT: t + 0.1)
    #expect(e.stateKind == .sliding)
    #expect(sink.count(.stepVolume(1, fine: false)) == 16)
}

@Test func pausingEndsActiveSlide() {
    let (e, sink, fb) = makeEngine()
    let t = e.drive(fb, id: 1, from: (115, 15), to: (115, 35), startT: 0)
    #expect(e.stateKind == .sliding)
    let steps = stepCount(sink)
    e.setPaused(true)
    #expect(e.stateKind == .idle)
    #expect(sink.count(.freezeCursor(false)) == 1)
    e.drive(fb, id: 1, from: (115, 36), to: (115, 75), startT: t + 0.008)
    #expect(e.stateKind == .idle)
    #expect(stepCount(sink) == steps)

    // An app switch is committed, not cancelled.
    let (e2, sink2, _) = makeEngine()
    e2.drive(fb, id: 1, from: (30, 78), to: (54, 78), startT: 0)
    #expect(sink2.count(.appSwitchStep(1)) == 2)
    e2.setPaused(true)
    #expect(e2.stateKind == .idle)
    #expect(sink2.count(.appSwitchCommit) == 1)
    #expect(sink2.contains(.appSwitchCancel) == false)
    #expect(sink2.count(.freezeCursor(false)) == 1)

    // Any other state returns to idle silently.
    let (e3, sink3, _) = makeEngine()
    e3.process(fb.frame(t: 0, [(1, 115, 15)]))
    #expect(e3.stateKind == .candidate)
    e3.setPaused(true)
    #expect(e3.stateKind == .idle)
    #expect(sink3.commands.isEmpty)
}

@Test func pauseDuringLostCommits() {
    let (e, sink, fb) = makeEngine()
    let t = e.drive(fb, id: 1, from: (30, 78), to: (54, 78), startT: 0)
    e.process(fb.frame(t: t + 0.008, []))
    #expect(e.stateKind == .lost)
    e.setPaused(true)
    #expect(e.stateKind == .idle)
    #expect(sink.count(.appSwitchCommit) == 1)
    #expect(sink.count(.appSwitchCancel) == 0)
    #expect(sink.count(.freezeCursor(false)) == 1)
    e.tick(now: t + 1)
    #expect(sink.count(.appSwitchCommit) == 1)
}

// MARK: - Configuration

@Test func swappedSidesChangeCommandType() {
    var cfg = EngineConfig()
    cfg.left = .volume
    cfg.right = .brightness
    let (e, sink, fb) = makeEngine(cfg)
    let t = e.drive(fb, id: 1, from: (115, 15), to: (115, 75), startT: 0)
    #expect(sink.count(.stepBrightness(1, fine: false)) == 16)
    #expect(sink.count(.stepVolume(1, fine: false)) == 0)
    e.process(fb.frame(t: t + 0.008, []))
    e.tick(now: t + 1)
    sink.removeAll()
    e.drive(fb, id: 2, from: (5, 15), to: (5, 75), startT: t + 1.1)
    #expect(sink.count(.stepVolume(1, fine: false)) == 16)
    #expect(sink.count(.stepBrightness(1, fine: false)) == 0)
}

@Test func resetEmitsFreezeOffOnlyWhenFrozen() {
    let (e, sink, fb) = makeEngine()
    e.reset()
    #expect(sink.commands.isEmpty)
    e.drive(fb, id: 1, from: (115, 15), to: (115, 35), startT: 0)
    #expect(e.stateKind == .sliding)
    e.reset()
    #expect(e.stateKind == .idle)
    #expect(sink.count(.freezeCursor(false)) == 1)

    var cfg = EngineConfig()
    cfg.freezeCursor = false
    let (e2, sink2, _) = makeEngine(cfg)
    e2.drive(fb, id: 1, from: (115, 15), to: (115, 35), startT: 0)
    #expect(e2.stateKind == .sliding)
    e2.reset()
    #expect(e2.stateKind == .idle)
    #expect(sink2.count(.freezeCursor(false)) == 0)
    #expect(sink2.count(.freezeCursor(true)) == 0)
}

private extension Frame {
    /// The same frame without the touch `id`.
    func withoutFinger(_ id: Int32) -> Frame {
        var copy = self
        var touches = TouchBuffer()
        for index in 0 ..< self.touches.count where self.touches[index].id != id {
            touches.append(self.touches[index])
        }
        copy.touches = touches
        return copy
    }
}
