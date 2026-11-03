import Foundation
import Testing
@testable import TrrekEngine

// swiftlint:disable:next large_tuple
private func makeEngine(_ config: EngineConfig = EngineConfig()) -> (GestureEngine, RecordingSink, FrameBuilder) {
    let sink = RecordingSink()
    let engine = GestureEngine(config: config, sink: sink)
    return (engine, sink, FrameBuilder())
}

/// One finger down at `t` on (`xMM`, `yMM`), lifted 0.1 s later. Returns the lift time.
@discardableResult
private func tap(
    _ engine: GestureEngine,
    _ fb: FrameBuilder,
    id: Int32,
    at position: (xMM: Float, yMM: Float),
    t: TimeInterval
) -> TimeInterval {
    engine.process(fb.frame(t: t, [(id, position.xMM, position.yMM)]))
    let lift = t + 0.1
    engine.process(fb.frame(t: lift, []))
    return lift
}

// swiftlint:disable:next large_tuple
private let threeFingers: [(id: Int32, xMM: Float, yMM: Float)] = [(1, 40, 40), (2, 60, 40), (3, 80, 40)]

private func middleClickConfig() -> EngineConfig {
    var cfg = EngineConfig()
    cfg.middleClickEnabled = true
    return cfg
}

// MARK: - Corner and media double-taps

@Test func plainEdgeTapEmitsNothing() {
    let (e, sink, fb) = makeEngine()
    e.process(fb.frame(t: 0, [(1, 115, 40)]))
    #expect(e.stateKind == .candidate)
    e.process(fb.frame(t: 0.1, []))
    #expect(sink.commands.isEmpty)
    #expect(e.stateKind == .idle)
}

@Test func cornerDoubleTapWithinWindowMutes() {
    var cfg = EngineConfig()
    cfg.bottomRight = .mute
    let (e, sink, fb) = makeEngine(cfg)
    let lift = tap(e, fb, id: 1, at: (115, 5), t: 0)
    #expect(sink.commands.isEmpty)
    #expect(e.stateKind == .idle)
    tap(e, fb, id: 2, at: (115, 5), t: lift + 0.30)
    #expect(sink.commands == [.mute, .haptic(.tap)])
    #expect(sink.count(.mute) == 1)
    #expect(sink.count(.haptic(.tap)) == 1)
    #expect(e.stateKind == .idle)

    // The pair is consumed: a third tap right after starts a new pair instead of muting again.
    tap(e, fb, id: 3, at: (115, 5), t: lift + 0.60)
    #expect(sink.count(.mute) == 1)
}

@Test func cornerDoubleTapOutsideWindowDoesNothing() {
    var cfg = EngineConfig()
    cfg.bottomRight = .mute
    let (e, sink, fb) = makeEngine(cfg)
    let lift = tap(e, fb, id: 1, at: (115, 5), t: 0)
    tap(e, fb, id: 2, at: (115, 5), t: lift + 0.36)
    #expect(sink.count(.mute) == 0)
    #expect(sink.commands.isEmpty)
    #expect(e.stateKind == .idle)
}

@Test func cornerDoubleTapOffDoesNothing() {
    let (e, sink, fb) = makeEngine()
    #expect(EngineConfig().bottomRight == .off)
    let lift = tap(e, fb, id: 1, at: (115, 5), t: 0)
    tap(e, fb, id: 2, at: (115, 5), t: lift + 0.30)
    #expect(sink.commands.isEmpty)
    #expect(e.stateKind == .idle)
}

@Test func screenshotCornerEmitsScreenshot() {
    var cfg = EngineConfig()
    cfg.topLeft = .screenshot
    let (e, sink, fb) = makeEngine(cfg)
    let lift = tap(e, fb, id: 1, at: (5, 75), t: 0)
    tap(e, fb, id: 2, at: (5, 75), t: lift + 0.30)
    #expect(sink.commands == [.screenshot, .haptic(.tap)])
    #expect(sink.count(.mute) == 0)
}

@Test func mediaEdgeDoubleTapPlaysPauses() {
    var cfg = EngineConfig()
    cfg.bottom = .media
    let (e, sink, fb) = makeEngine(cfg)
    let lift = tap(e, fb, id: 1, at: (60, 5), t: 0)
    #expect(sink.commands.isEmpty)
    tap(e, fb, id: 2, at: (60, 5), t: lift + 0.30)
    #expect(sink.commands == [.mediaPlayPause, .haptic(.tap)])
    #expect(sink.count(.mediaPlayPause) == 1)
    #expect(e.stateKind == .idle)
}

@Test func mediaEdgeSlideSkipsTrack() {
    var cfg = EngineConfig()
    cfg.bottom = .media

    let (right, rightSink, fb) = makeEngine(cfg)
    right.drive(fb, id: 1, from: (40, 5), to: (60, 5), startT: 0)
    #expect(rightSink.count(.mediaNext) == 1)
    #expect(rightSink.count(.mediaPrevious) == 0)
    #expect(rightSink.count(.mediaPlayPause) == 0)

    let (left, leftSink, _) = makeEngine(cfg)
    left.drive(fb, id: 1, from: (60, 5), to: (40, 5), startT: 0)
    #expect(leftSink.count(.mediaPrevious) == 1)
    #expect(leftSink.count(.mediaNext) == 0)
}

@Test func lastTapClearedByInterveningGesture() {
    var cfg = middleClickConfig()
    cfg.bottomRight = .mute
    let (e, sink, fb) = makeEngine(cfg)
    let lift = tap(e, fb, id: 1, at: (115, 5), t: 0)
    // A three-finger tap between the two corner taps breaks the pair.
    e.process(fb.frame(t: lift + 0.05, threeFingers))
    #expect(e.stateKind == .threeFinger)
    e.process(fb.frame(t: lift + 0.10, []))
    #expect(sink.count(.middleClick) == 1)
    tap(e, fb, id: 4, at: (115, 5), t: lift + 0.15)
    #expect(sink.count(.mute) == 0)
    #expect(sink.commands == [.middleClick, .haptic(.tap)])
    #expect(e.stateKind == .idle)
}

// MARK: - Three-finger middle click

@Test func threeFingerTapEmitsMiddleClick() {
    let (e, sink, fb) = makeEngine(middleClickConfig())
    e.process(fb.frame(t: 0, threeFingers))
    #expect(e.stateKind == .threeFinger)
    e.process(fb.frame(t: 0.05, []))
    #expect(sink.commands == [.middleClick, .haptic(.tap)])
    #expect(sink.count(.middleClick) == 1)
    #expect(sink.count(.haptic(.tap)) == 1)
    #expect(e.stateKind == .idle)
}

@Test func threeFingerStaggeredLandingStillCounts() {
    let (e, sink, fb) = makeEngine(middleClickConfig())
    e.process(fb.frame(t: 0, [(1, 40, 40)]))
    #expect(e.stateKind == .spent)
    e.process(fb.frame(t: 0.03, [(1, 40, 40), (2, 60, 40)]))
    #expect(e.stateKind == .spent)
    e.process(fb.frame(t: 0.06, threeFingers))
    #expect(e.stateKind == .threeFinger)
    // The fingers lift one by one; the click comes when the last one is up.
    e.process(fb.frame(t: 0.10, [(2, 60, 40), (3, 80, 40)]))
    e.process(fb.frame(t: 0.12, [(3, 80, 40)]))
    #expect(sink.commands.isEmpty)
    #expect(e.stateKind == .threeFinger)
    e.process(fb.frame(t: 0.15, []))
    #expect(sink.count(.middleClick) == 1)
    #expect(sink.count(.haptic(.tap)) == 1)
    #expect(e.stateKind == .idle)
}

@Test func threeFingerDisabledDoesNothing() {
    let (e, sink, fb) = makeEngine()
    #expect(EngineConfig().middleClickEnabled == false)
    e.process(fb.frame(t: 0, threeFingers))
    #expect(e.stateKind == .spent)
    e.process(fb.frame(t: 0.05, []))
    #expect(sink.commands.isEmpty)
    #expect(e.stateKind == .idle)
}

@Test func threeFingerMovementCancels() {
    let (e, sink, fb) = makeEngine(middleClickConfig())
    e.process(fb.frame(t: 0, threeFingers))
    #expect(e.stateKind == .threeFinger)
    e.process(fb.frame(t: 0.05, [(1, 43, 40), (2, 60, 40), (3, 80, 40)]))
    #expect(e.stateKind == .spent)
    e.process(fb.frame(t: 0.1, []))
    #expect(sink.count(.middleClick) == 0)
    #expect(sink.commands.isEmpty)
    #expect(e.stateKind == .idle)
}

@Test func threeFingerTooLongCancels() {
    let (e, sink, fb) = makeEngine(middleClickConfig())
    e.process(fb.frame(t: 0, threeFingers))
    e.process(fb.frame(t: 0.1, threeFingers))
    e.process(fb.frame(t: 0.2, threeFingers))
    #expect(e.stateKind == .threeFinger)
    e.process(fb.frame(t: 0.35, threeFingers))
    #expect(e.stateKind == .spent)
    e.process(fb.frame(t: 0.36, []))
    #expect(sink.count(.middleClick) == 0)
    #expect(sink.commands.isEmpty)
    #expect(e.stateKind == .idle)
}

@Test func fourthFingerCancels() {
    let (e, sink, fb) = makeEngine(middleClickConfig())
    e.process(fb.frame(t: 0, threeFingers))
    #expect(e.stateKind == .threeFinger)
    e.process(fb.frame(t: 0.05, threeFingers + [(4, 100, 40)]))
    #expect(e.stateKind == .spent)
    // Back to three fingers does not re-arm the click.
    e.process(fb.frame(t: 0.08, threeFingers))
    #expect(e.stateKind == .spent)
    e.process(fb.frame(t: 0.12, []))
    #expect(sink.count(.middleClick) == 0)
    #expect(sink.commands.isEmpty)
    #expect(e.stateKind == .idle)
}

// MARK: - Regressions: `spent` keeps landing positions

@Test func slideCancelThenThirdFingerDoesNotMiddleClick() {
    let (e, sink, fb) = makeEngine(middleClickConfig())
    e.process(fb.frame(t: 0, [(1, 115, 40)]))
    e.process(fb.frame(t: 0.02, [(1, 115, 44)]))
    #expect(e.stateKind == .sliding)
    e.process(fb.frame(t: 0.04, [(1, 115, 44), (2, 60, 40)]))
    #expect(e.stateKind == .spent)
    // The slide finger moved 4 mm from where it landed, so three fingers cannot arm a click.
    e.process(fb.frame(t: 0.06, [(1, 115, 44), (2, 60, 40), (3, 80, 40)]))
    #expect(e.stateKind == .spent)
    e.process(fb.frame(t: 0.09, []))
    #expect(sink.commands == [
        .freezeCursor(true), .haptic(.start), .stepVolume(1, fine: false), .haptic(.step), .freezeCursor(false)
    ])
    #expect(sink.count(.middleClick) == 0)
    #expect(e.stateKind == .idle)
}

@Test func threeFingerCancelThenReplacementFingerDoesNotMiddleClick() {
    let (e, sink, fb) = makeEngine(middleClickConfig())
    e.process(fb.frame(t: 0, threeFingers))
    e.process(fb.frame(t: 0.03, [(1, 43, 40), (2, 60, 40), (3, 80, 40)]))
    #expect(e.stateKind == .spent)
    // Finger 3 lifts and finger 4 lands on the same frame; finger 1 is still 3 mm from where it landed.
    e.process(fb.frame(t: 0.06, [(1, 43, 40), (2, 60, 40), (4, 100, 40)]))
    #expect(e.stateKind == .spent)
    e.process(fb.frame(t: 0.09, []))
    #expect(sink.commands.isEmpty)
    #expect(sink.count(.middleClick) == 0)
    #expect(e.stateKind == .idle)
}

@Test func disablingMiddleClickMidGestureDoesNotClick() {
    let (e, sink, fb) = makeEngine(middleClickConfig())
    e.process(fb.frame(t: 0, threeFingers))
    #expect(e.stateKind == .threeFinger)
    e.update(config: EngineConfig())
    #expect(e.stateKind == .spent)
    e.process(fb.frame(t: 0.05, []))
    #expect(sink.commands.isEmpty)
    #expect(e.stateKind == .idle)
}
