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

private func freezeCount(_ sink: RecordingSink) -> Int {
    sink.count(.freezeCursor(true)) + sink.count(.freezeCursor(false))
}

@Test func sixteenStepsForSixtyMillimetres() {
    let sink = RecordingSink(); let e = GestureEngine(config: EngineConfig(), sink: sink); let fb = FrameBuilder()
    e.drive(fb, id: 1, from: (115, 15), to: (115, 75), startT: 0)
    #expect(sink.count(.stepVolume(1, fine: false)) == 16)
    #expect(sink.count(.haptic(.step)) == 16)
    #expect(sink.count(.haptic(.start)) == 1)
    #expect(stepCount(sink) == 16)
    #expect(e.stateKind == .sliding)
    #expect(sink.recorded.allSatisfy { $0.device == 1 })
}

@Test func belowSlideStartNoCommands() {
    let (e, sink, fb) = makeEngine()
    e.drive(fb, id: 1, from: (115, 15), to: (115, 17.5), startT: 0)
    #expect(sink.commands.isEmpty)
    #expect(e.stateKind == .candidate)
}

@Test func downwardSlideEmitsNegativeSteps() {
    let (e, sink, fb) = makeEngine()
    e.drive(fb, id: 1, from: (115, 75), to: (115, 15), startT: 0)
    #expect(sink.count(.stepVolume(-1, fine: false)) == 16)
    #expect(sink.count(.stepVolume(1, fine: false)) == 0)
    #expect(sink.count(.haptic(.step)) == 16)
}

@Test func precisionSetsFineFlag() {
    var cfg = EngineConfig()
    cfg.precision = true
    let (e, sink, fb) = makeEngine(cfg)
    e.drive(fb, id: 1, from: (115, 15), to: (115, 75), startT: 0)
    #expect(sink.count(.stepVolume(1, fine: true)) == 16)
    #expect(sink.count(.stepVolume(1, fine: false)) == 0)
}

@Test func perpendicularMoveAbortsCandidate() {
    let (e, sink, fb) = makeEngine()
    let t = e.drive(fb, id: 1, from: (115, 40), to: (110, 40), startT: 0)
    #expect(e.stateKind == .spent)
    e.drive(fb, id: 1, from: (110, 40), to: (110, 70), startT: t + 0.008)
    #expect(sink.commands.isEmpty)
    #expect(e.stateKind == .spent)
}

@Test func secondFingerCancelsSlide() {
    let (e, sink, fb) = makeEngine()
    var t = e.drive(fb, id: 1, from: (115, 15), to: (115, 35), startT: 0)
    let steps = stepCount(sink)
    #expect(steps == 5)
    t += 0.008
    e.process(fb.frame(t: t, [(1, 115, 36), (2, 60, 40)]))
    #expect(e.stateKind == .spent)
    #expect(sink.count(.freezeCursor(false)) == 1)
    t += 0.008
    e.process(fb.frame(t: t, [(1, 115, 50), (2, 60, 40)]))
    #expect(stepCount(sink) == steps)
    t += 0.008
    e.process(fb.frame(t: t, [(2, 60, 40)]))
    #expect(e.stateKind == .spent)
    t += 0.008
    e.process(fb.frame(t: t, []))
    #expect(e.stateKind == .idle)
    #expect(stepCount(sink) == steps)
    #expect(sink.count(.freezeCursor(false)) == 1)
}

@Test func lostFingerReturnsWithinTimeoutContinues() {
    let (e, sink, fb) = makeEngine()
    var t = e.drive(fb, id: 1, from: (115, 15), to: (115, 35), startT: 0)
    #expect(stepCount(sink) == 5)
    t += 0.008
    e.process(fb.frame(t: t, []))
    #expect(e.stateKind == .lost)
    e.process(fb.frame(t: t + 0.17, [(1, 115, 35)]))
    #expect(e.stateKind == .sliding)
    e.drive(fb, id: 1, from: (115, 35), to: (115, 55), startT: t + 0.178)
    #expect(sink.count(.stepVolume(1, fine: false)) == 10)
    #expect(sink.count(.freezeCursor(false)) == 0)
    #expect(sink.count(.haptic(.start)) == 1)
}

@Test func lostFingerExpiresCommits() {
    let (e, sink, fb) = makeEngine()
    var t = e.drive(fb, id: 1, from: (115, 15), to: (115, 35), startT: 0)
    t += 0.008
    e.process(fb.frame(t: t, []))
    #expect(e.stateKind == .lost)
    #expect(sink.count(.freezeCursor(false)) == 0)
    e.process(fb.frame(t: t + 0.181, []))
    #expect(e.stateKind == .idle)
    #expect(sink.count(.freezeCursor(false)) == 1)
}

@Test func watchdogTickCommits() {
    let (e, sink, fb) = makeEngine()
    let last = e.drive(fb, id: 1, from: (115, 15), to: (115, 35), startT: 0)
    e.tick(now: last + 0.1)
    #expect(e.stateKind == .sliding)
    e.tick(now: last + 0.181)
    #expect(e.stateKind == .idle)
    #expect(sink.count(.freezeCursor(false)) == 1)
}

@Test func watchdogTickExpiresLost() {
    let (e, sink, fb) = makeEngine()
    var t = e.drive(fb, id: 1, from: (115, 15), to: (115, 35), startT: 0)
    t += 0.008
    e.process(fb.frame(t: t, []))
    e.tick(now: t + 0.1)
    #expect(e.stateKind == .lost)
    e.tick(now: t + 0.181)
    #expect(e.stateKind == .idle)
    #expect(sink.count(.freezeCursor(false)) == 1)
}

@Test func backwardsTimestampDoesNotCommit() {
    let (e, sink, fb) = makeEngine()
    let last = e.drive(fb, id: 1, from: (115, 15), to: (115, 35), startT: 0)
    let before = sink.commands.count
    e.tick(now: last - 1)
    #expect(e.stateKind == .sliding)
    #expect(sink.commands.count == before)
}

@Test func reusedIDAfterLostExpiryStartsFresh() {
    let (e, sink, fb) = makeEngine()
    var t = e.drive(fb, id: 1, from: (115, 15), to: (115, 35), startT: 0)
    t += 0.008
    e.process(fb.frame(t: t, []))
    let steps = stepCount(sink)
    e.process(fb.frame(t: t + 0.2, [(1, 115, 15)]))
    #expect(e.stateKind == .candidate)
    #expect(sink.count(.freezeCursor(false)) == 1)
    #expect(stepCount(sink) == steps)
    e.drive(fb, id: 1, from: (115, 15), to: (115, 17), startT: t + 0.208)
    #expect(e.stateKind == .candidate)
    #expect(stepCount(sink) == steps)
}

@Test func switchAppsStepsAndCommit() {
    let (e, sink, fb) = makeEngine()
    var t = e.drive(fb, id: 1, from: (30, 78), to: (54, 78), startT: 0)
    #expect(sink.count(.appSwitchStep(1)) == 2)
    #expect(sink.count(.haptic(.step)) == 2)
    t += 0.008
    e.process(fb.frame(t: t, []))
    #expect(sink.contains(.appSwitchCommit) == false)
    e.process(fb.frame(t: t + 0.181, []))
    #expect(sink.count(.appSwitchCommit) == 1)
    #expect(sink.contains(.appSwitchCancel) == false)
    #expect(e.stateKind == .idle)
}

@Test func switchAppsSecondFingerCancels() {
    let (e, sink, fb) = makeEngine()
    var t = e.drive(fb, id: 1, from: (30, 78), to: (54, 78), startT: 0)
    t += 0.008
    e.process(fb.frame(t: t, [(1, 55, 78), (2, 60, 40)]))
    #expect(sink.count(.appSwitchCancel) == 1)
    #expect(sink.contains(.appSwitchCommit) == false)
    #expect(sink.count(.freezeCursor(false)) == 1)
    #expect(e.stateKind == .spent)
    e.process(fb.frame(t: t + 0.008, []))
    #expect(e.stateKind == .idle)
    #expect(sink.contains(.appSwitchCommit) == false)
}

@Test func scrubStepsAndCommit() {
    var cfg = EngineConfig()
    cfg.top = .scrubVideo
    let (e, sink, fb) = makeEngine(cfg)
    var t = e.drive(fb, id: 1, from: (30, 78), to: (42, 78), startT: 0)
    #expect(sink.count(.scrubStep(1)) == 2)
    t += 0.008
    e.process(fb.frame(t: t, []))
    e.process(fb.frame(t: t + 0.181, []))
    #expect(sink.count(.scrubCommit) == 1)
    #expect(sink.contains(.scrubCancel) == false)
    #expect(sink.count(.freezeCursor(false)) == 1)
    #expect(e.stateKind == .idle)
}

@Test func mediaSlideSkipsTracks() {
    var cfg = EngineConfig()
    cfg.right = .media
    let (e, sink, fb) = makeEngine(cfg)
    let t = e.drive(fb, id: 1, from: (115, 15), to: (115, 55), startT: 0)
    #expect(sink.count(.mediaNext) == 2)
    e.drive(fb, id: 1, from: (115, 55), to: (115, 15), startT: t + 0.008)
    #expect(sink.count(.mediaPrevious) == 2)
}

@Test func updateConfigDuringSlideCommits() {
    let (e, sink, fb) = makeEngine()
    e.drive(fb, id: 1, from: (115, 15), to: (115, 35), startT: 0)
    #expect(e.stateKind == .sliding)
    var cfg = EngineConfig()
    cfg.precision = true
    e.update(config: cfg)
    #expect(e.stateKind == .idle)
    #expect(sink.count(.freezeCursor(false)) == 1)

    let (e2, sink2, fb2) = makeEngine()
    e2.drive(fb2, id: 1, from: (30, 78), to: (54, 78), startT: 0)
    e2.update(config: EngineConfig())
    #expect(e2.stateKind == .idle)
    #expect(sink2.count(.appSwitchCommit) == 1)
    #expect(sink2.count(.freezeCursor(false)) == 1)
}

@Test func updateConfigAppliesToNextSlide() {
    let (e, sink, fb) = makeEngine()
    var cfg = EngineConfig()
    cfg.right = .brightness
    e.update(config: cfg)
    e.drive(fb, id: 1, from: (115, 15), to: (115, 35), startT: 0)
    #expect(sink.count(.stepBrightness(1, fine: false)) == 5)
    #expect(sink.count(.stepVolume(1, fine: false)) == 0)
}

@Test func frameFromOtherDeviceIgnoredWhileSliding() {
    let (e, sink, fb) = makeEngine()
    var other = FrameBuilder()
    other.deviceID = 2
    var t = e.drive(fb, id: 1, from: (115, 15), to: (115, 35), startT: 0)
    let before = sink.commands.count
    t += 0.008
    e.process(other.frame(t: t, []))
    #expect(e.stateKind == .sliding)
    e.process(other.frame(t: t + 0.008, [(1, 115, 70), (2, 60, 40)]))
    #expect(e.stateKind == .sliding)
    e.process(other.frame(t: t + 0.3, []))
    #expect(e.stateKind == .sliding)
    #expect(sink.commands.count == before)
    e.drive(fb, id: 1, from: (115, 35), to: (115, 55), startT: t + 0.016)
    #expect(sink.count(.stepVolume(1, fine: false)) == 10)
}

@Test func freezeCursorEmittedOncePerSlide() {
    let (e, sink, fb) = makeEngine()
    var t = e.drive(fb, id: 1, from: (115, 15), to: (115, 75), startT: 0)
    t += 0.008
    e.process(fb.frame(t: t, []))
    e.process(fb.frame(t: t + 0.181, []))
    #expect(sink.count(.freezeCursor(true)) == 1)
    #expect(sink.count(.freezeCursor(false)) == 1)
    #expect(sink.commands.first == .freezeCursor(true))
    #expect(sink.commands.dropFirst().first == .haptic(.start))
    #expect(sink.commands.last == .freezeCursor(false))
}

@Test func freezeCursorDisabledInConfigEmitsNothing() {
    var cfg = EngineConfig()
    cfg.freezeCursor = false
    let (e, sink, fb) = makeEngine(cfg)
    var t = e.drive(fb, id: 1, from: (115, 15), to: (115, 75), startT: 0)
    t += 0.008
    e.process(fb.frame(t: t, []))
    e.process(fb.frame(t: t + 0.181, []))
    #expect(freezeCount(sink) == 0)
    #expect(sink.count(.haptic(.start)) == 1)
    #expect(sink.count(.stepVolume(1, fine: false)) == 16)
}

@Test func cornerCandidateBindsToVerticalEdgeOnVerticalMove() {
    let (e, sink, fb) = makeEngine()
    e.process(fb.frame(t: 0, [(1, 115, 5)]))
    #expect(e.stateKind == .candidate)
    e.drive(fb, id: 1, from: (115, 5), to: (115, 40), startT: 0.008)
    #expect(e.stateKind == .sliding)
    #expect(sink.count(.stepVolume(1, fine: false)) == 9)
    #expect(sink.count(.stepKeyboardBacklight(1, fine: false)) == 0)
}

@Test func cornerCandidateBindsToHorizontalEdgeOnHorizontalMove() {
    let (e, sink, fb) = makeEngine()
    e.drive(fb, id: 1, from: (115, 5), to: (90, 5), startT: 0)
    #expect(e.stateKind == .sliding)
    #expect(sink.count(.stepKeyboardBacklight(-1, fine: false)) == 6)
    #expect(sink.count(.stepVolume(1, fine: false)) == 0)
}

@Test func liftInCandidateReturnsToIdle() {
    let (e, sink, fb) = makeEngine()
    e.process(fb.frame(t: 0, [(1, 115, 40)]))
    #expect(e.stateKind == .candidate)
    e.process(fb.frame(t: 0.5, []))
    #expect(e.stateKind == .idle)
    #expect(sink.commands.isEmpty)
}

@Test func touchOutsideStripIsSpentUntilLift() {
    let (e, sink, fb) = makeEngine()
    e.drive(fb, id: 1, from: (60, 40), to: (115, 40), startT: 0)
    #expect(e.stateKind == .spent)
    e.process(fb.frame(t: 1, []))
    #expect(e.stateKind == .idle)
    #expect(sink.commands.isEmpty)
}

@Test func resetDuringSlideUnfreezesWithoutCommit() {
    let (e, sink, fb) = makeEngine()
    e.drive(fb, id: 1, from: (30, 78), to: (54, 78), startT: 0)
    e.reset()
    #expect(e.stateKind == .idle)
    #expect(sink.count(.freezeCursor(false)) == 1)
    #expect(sink.contains(.appSwitchCommit) == false)
    #expect(sink.contains(.appSwitchCancel) == false)
    e.reset()
    #expect(sink.count(.freezeCursor(false)) == 1)
}
