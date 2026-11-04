import Foundation
import Testing
@testable import TrrekEngine

// Synthetic slides for the actions every edge can run. The frame builder's pad is 120 x 80 mm: the top strip is at
// y 78, the right strip at x 115, the left strip at x 5. Forward is rightward on a horizontal edge and upward on a
// vertical one.

// swiftlint:disable:next large_tuple
private func engine(_ edge: Edge, _ action: EdgeAction) -> (GestureEngine, RecordingSink, FrameBuilder) {
    var config = EngineConfig()
    switch edge {
    case .left: config.left = action
    case .right: config.right = action
    case .top: config.top = action
    case .bottom: config.bottom = action
    }
    let sink = RecordingSink()
    return (GestureEngine(config: config, sink: sink), sink, FrameBuilder())
}

/// The step command an edge action emits for one step in `direction`.
private func step(_ action: EdgeAction, _ direction: Int) -> GestureCommand {
    switch action {
    case .switchTabs: .tabSwitchStep(direction)
    case .switchDesktops: .desktopSwitchStep(direction)
    case .zoom: .zoomStep(direction)
    case .undoRedo: .undoRedoStep(direction)
    case .switchApps: .appSwitchStep(direction)
    case .keyboardBacklight: .stepKeyboardBacklight(direction, fine: false)
    default: .mediaPlayPause
    }
}

/// The new keyboard actions with their step distance in mm.
private let keyboardActions: [(EdgeAction, Float)] = [
    (.switchTabs, 12),
    (.switchDesktops, 20),
    (.zoom, 8),
    (.undoRedo, 10)
]

@Test(arguments: keyboardActions)
func horizontalEdgeStepsForwardToTheRight(action: EdgeAction, stepMM: Float) {
    let (e, sink, fb) = engine(.top, action)
    // 40 mm to the right, then 40 mm back to the left.
    let t = e.drive(fb, id: 1, from: (30, 78), to: (70, 78), startT: 0)
    let forward = Int(40 / stepMM)
    #expect(sink.count(step(action, 1)) == forward)
    #expect(sink.count(step(action, -1)) == 0)
    #expect(sink.count(.haptic(.step)) == forward)
    e.drive(fb, id: 1, from: (70, 78), to: (30, 78), startT: t + 0.008)
    #expect(sink.count(step(action, -1)) == forward)
}

@Test(arguments: keyboardActions)
func verticalEdgeStepsForwardUpward(action: EdgeAction, stepMM: Float) {
    let (e, sink, fb) = engine(.right, action)
    // 40 mm up, then 40 mm down.
    let t = e.drive(fb, id: 1, from: (115, 15), to: (115, 55), startT: 0)
    let forward = Int(40 / stepMM)
    #expect(sink.count(step(action, 1)) == forward)
    #expect(sink.count(step(action, -1)) == 0)
    e.drive(fb, id: 1, from: (115, 55), to: (115, 15), startT: t + 0.008)
    #expect(sink.count(step(action, -1)) == forward)
}

@Test(arguments: keyboardActions)
func keyboardActionsNeedNoCommitOrCancel(action: EdgeAction, stepMM _: Float) {
    let (e, sink, fb) = engine(.left, action)
    var t = e.drive(fb, id: 1, from: (5, 15), to: (5, 55), startT: 0)
    t += 0.008
    e.process(fb.frame(t: t, []))
    e.process(fb.frame(t: t + 0.181, []))
    #expect(e.stateKind == .idle)
    #expect(!sink.contains(.appSwitchCommit))
    #expect(!sink.contains(.scrubCommit))
    #expect(sink.commands.last == .freezeCursor(false))

    // A second finger cancels the slide without a cancel command either.
    let (cancelled, cancelSink, cfb) = engine(.left, action)
    let end = cancelled.drive(cfb, id: 1, from: (5, 15), to: (5, 55), startT: 0)
    cancelled.process(cfb.frame(t: end + 0.008, [(1, 5, 56), (2, 60, 40)]))
    #expect(!cancelSink.contains(.appSwitchCancel))
    #expect(!cancelSink.contains(.scrubCancel))
    #expect(cancelSink.count(.freezeCursor(false)) == 1)
}

@Test func switchAppsOnASideEdgeHoldsCommitsAndCancels() {
    // Upward is the next app on a vertical edge; lifting commits, a second finger cancels.
    let (e, sink, fb) = engine(.left, .switchApps)
    var t = e.drive(fb, id: 1, from: (5, 15), to: (5, 39), startT: 0)
    #expect(sink.count(.appSwitchStep(1)) == 2)
    t = e.drive(fb, id: 1, from: (5, 39), to: (5, 27), startT: t + 0.008)
    #expect(sink.count(.appSwitchStep(-1)) == 1)
    t += 0.008
    e.process(fb.frame(t: t, []))
    e.process(fb.frame(t: t + 0.181, []))
    #expect(sink.count(.appSwitchCommit) == 1)
    #expect(!sink.contains(.appSwitchCancel))

    let (cancelled, cancelSink, cfb) = engine(.right, .switchApps)
    let end = cancelled.drive(cfb, id: 1, from: (115, 15), to: (115, 39), startT: 0)
    cancelled.process(cfb.frame(t: end + 0.008, [(1, 115, 40), (2, 60, 40)]))
    #expect(cancelSink.count(.appSwitchCancel) == 1)
    #expect(!cancelSink.contains(.appSwitchCommit))
}

@Test func keyboardBacklightRunsOnASideEdge() {
    let (e, sink, fb) = engine(.right, .keyboardBacklight)
    e.drive(fb, id: 1, from: (115, 15), to: (115, 30), startT: 0)
    #expect(sink.count(.stepKeyboardBacklight(1, fine: false)) == 4)
    #expect(sink.count(.stepVolume(1, fine: false)) == 0)
}

@Test func mediaEdgeDoubleTapPlaysOnASideEdge() {
    let (e, sink, fb) = engine(.left, .media)
    e.process(fb.frame(t: 0, [(1, 5, 40)]))
    e.process(fb.frame(t: 0.1, []))
    e.process(fb.frame(t: 0.3, [(2, 5, 40)]))
    e.process(fb.frame(t: 0.4, []))
    #expect(sink.commands == [.mediaPlayPause, .haptic(.tap)])
}

@Test func scaledStepsFollowTheSensitivity() {
    // The shortest and longest step distances the sensitivity setting produces still step exactly.
    for (multiplier, steps) in [(Float(0.6), 26), (Float(1.6), 10)] {
        var config = EngineConfig()
        config.thresholds.stepMM *= multiplier
        let sink = RecordingSink()
        let e = GestureEngine(config: config, sink: sink)
        e.drive(FrameBuilder(), id: 1, from: (115, 15), to: (115, 75), startT: 0)
        #expect(sink.count(.stepVolume(1, fine: false)) == steps)
    }
}

// MARK: - Corners

private let cornerCommands: [(CornerAction, GestureCommand)] = [
    (.mute, .mute),
    (.screenshot, .screenshot),
    (.playPause, .mediaPlayPause),
    (.missionControl, .missionControl),
    (.appWindows, .appWindows),
    (.showDesktop, .showDesktop),
    (.spotlight, .spotlight),
    (.lockScreen, .lockScreen),
    (.screenshotArea, .screenshotArea)
]

@Test func everyCornerActionHasACommand() {
    #expect(cornerCommands.map(\.0) == CornerAction.allCases.filter { $0 != .off })
    #expect(GestureEngine.command(for: .off) == nil)
}

@Test(arguments: cornerCommands)
func cornerDoubleTapFiresItsAction(action: CornerAction, command: GestureCommand) {
    var config = EngineConfig()
    config.topLeft = action
    let sink = RecordingSink()
    let e = GestureEngine(config: config, sink: sink)
    let fb = FrameBuilder()
    e.process(fb.frame(t: 0, [(1, 5, 75)]))
    e.process(fb.frame(t: 0.1, []))
    #expect(sink.commands.isEmpty)
    e.process(fb.frame(t: 0.3, [(2, 5, 75)]))
    e.process(fb.frame(t: 0.4, []))
    #expect(sink.commands == [command, .haptic(.tap)])
}

// MARK: - Corners next to an edge that is off

/// Two quick taps on (`xMM`, `yMM`), the second 0.2 s after the first lifts.
private func doubleTap(_ engine: GestureEngine, _ fb: FrameBuilder, at position: (Float, Float)) {
    engine.process(fb.frame(t: 0, [(1, position.0, position.1)]))
    engine.process(fb.frame(t: 0.1, []))
    engine.process(fb.frame(t: 0.3, [(2, position.0, position.1)]))
    engine.process(fb.frame(t: 0.4, []))
}

@Test func cornerNextToAnOffEdgeStillFiresItsAction() {
    var config = EngineConfig()
    config.left = .off
    config.topLeft = .missionControl
    let sink = RecordingSink()
    let e = GestureEngine(config: config, sink: sink)
    let fb = FrameBuilder()
    #expect(Geometry.zone(of: Touch(id: 1, x: 5 / 120, y: 75 / 80, majorAxisMM: 8), in: fb.geometry, config: config)
        == .corner(.topLeft))
    doubleTap(e, fb, at: (5, 75))
    #expect(sink.commands == [.missionControl, .haptic(.tap)])
}

@Test func slideFromACornerTowardAnOffEdgeEmitsNothing() {
    var config = EngineConfig()
    config.left = .off
    config.topLeft = .missionControl
    let sink = RecordingSink()
    let e = GestureEngine(config: config, sink: sink)
    let fb = FrameBuilder()
    // Down along the left edge, which is off: the finger is spent, no step and no cursor freeze.
    let t = e.drive(fb, id: 1, from: (5, 75), to: (5, 40), startT: 0)
    #expect(sink.commands.isEmpty)
    #expect(e.stateKind == .spent)
    e.process(fb.frame(t: t + 0.008, []))

    // Along the top edge, which still runs its action, the same corner slides as before.
    e.drive(fb, id: 2, from: (5, 75), to: (40, 75), startT: t + 1)
    #expect(sink.count(.appSwitchStep(1)) == 2)
}

@Test func cornerBetweenTwoOffEdgesStillFiresItsAction() {
    var config = EngineConfig()
    config.left = .off
    config.top = .off
    config.topLeft = .lockScreen
    let sink = RecordingSink()
    let e = GestureEngine(config: config, sink: sink)
    let fb = FrameBuilder()
    doubleTap(e, fb, at: (5, 75))
    #expect(sink.commands == [.lockScreen, .haptic(.tap)])
    // The middles of both edges are still no zone at all.
    #expect(Geometry.zone(of: Touch(id: 1, x: 5 / 120, y: 0.5, majorAxisMM: 8), in: fb.geometry, config: config)
        == .none)
    #expect(Geometry.zone(of: Touch(id: 1, x: 0.5, y: 75 / 80, majorAxisMM: 8), in: fb.geometry, config: config)
        == .none)
}

// MARK: - Sensitivity at the slide start

@Test func highAndVeryHighSensitivityStepOnTheSlideStart() {
    // At High (0.8) the level step is 3 mm, the slide start distance; at Very High (0.6) it is 2.25 mm. Either way
    // the frame that starts the slide also emits the first step. At Standard (3.75 mm) a 3.2 mm slide emits none.
    for (multiplier, steps) in [(Float(0.8), 1), (Float(0.6), 1), (Float(1.0), 0)] {
        var config = EngineConfig()
        config.thresholds.stepMM *= multiplier
        let sink = RecordingSink()
        let e = GestureEngine(config: config, sink: sink)
        e.drive(FrameBuilder(), id: 1, from: (115, 15), to: (115, 18.2), startT: 0)
        #expect(e.stateKind == .sliding)
        #expect(sink.count(.stepVolume(1, fine: false)) == steps)
        if steps == 1 {
            #expect(sink.commands == [
                .freezeCursor(true), .haptic(.start), .stepVolume(1, fine: false), .haptic(.step)
            ])
        }
    }
}
