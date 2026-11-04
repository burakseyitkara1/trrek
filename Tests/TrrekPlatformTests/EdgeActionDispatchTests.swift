import CoreGraphics
import Testing
import TrrekEngine
import TrrekPlatform

/// The dispatcher with fake ports, for the keyboard steps and corner actions added with per-edge actions.
private struct Rig {
    let media = FakeMediaKeys()
    let keys = FakeKeys()
    let haptics = FakeHaptics()
    let missionControl = FakeMissionControl()
    let backlight = FakeBacklight(level: 0.5)
    let overlay = FakeOverlay()
    let dispatcher: CommandDispatcher

    init(withMissionControl: Bool = true) {
        dispatcher = CommandDispatcher(
            mediaKeys: media,
            keys: keys,
            mouse: FakeMouse(),
            haptics: haptics,
            freezer: FakeFreezer(),
            backlight: backlight,
            overlay: overlay,
            missionControl: withMissionControl ? missionControl : nil
        )
    }

    func send(_ commands: GestureCommand...) {
        for command in commands {
            dispatcher.handle(command, device: 1)
        }
    }
}

private enum Key {
    static let tab: CGKeyCode = 48
    static let leftArrow: CGKeyCode = 123
    static let rightArrow: CGKeyCode = 124
    static let equal: CGKeyCode = 24
    static let minus: CGKeyCode = 27
    static let zKey: CGKeyCode = 6
    static let space: CGKeyCode = 49
    static let qKey: CGKeyCode = 12
    static let four: CGKeyCode = 21
    static let command: CGKeyCode = 55
}

private let arrowControl: CGEventFlags = [.maskControl, .maskSecondaryFn, .maskNumericPad]

/// Unlike the app switcher, nothing is held down between steps.
@Test func tabStepsPressControlTab() {
    let rig = Rig()
    rig.send(.tabSwitchStep(1), .tabSwitchStep(-1))
    #expect(rig.keys.calls == [.press(Key.tab, .maskControl), .press(Key.tab, [.maskControl, .maskShift])])
}

@Test func desktopStepsPressControlArrows() {
    let rig = Rig()
    rig.send(.desktopSwitchStep(1), .desktopSwitchStep(-1))
    #expect(rig.keys.calls == [.press(Key.rightArrow, arrowControl), .press(Key.leftArrow, arrowControl)])
}

@Test func zoomStepsPressCommandEqualsAndMinus() {
    let rig = Rig()
    rig.send(.zoomStep(1), .zoomStep(-1))
    #expect(rig.keys.calls == [.press(Key.equal, .maskCommand), .press(Key.minus, .maskCommand)])
}

@Test func undoRedoStepsPressCommandZ() {
    let rig = Rig()
    rig.send(.undoRedoStep(1), .undoRedoStep(-1))
    #expect(rig.keys.calls == [.press(Key.zKey, [.maskCommand, .maskShift]), .press(Key.zKey, .maskCommand)])
}

@Test func frontAppStepsAreDroppedWhileTrrekIsFrontmost() {
    let rig = Rig()
    rig.dispatcher.ownAppFrontmost = true
    rig.send(.tabSwitchStep(1), .zoomStep(1), .undoRedoStep(-1), .scrubStep(1))
    #expect(rig.keys.calls.isEmpty)
    // Desktop switching is system-wide, so it still runs.
    rig.send(.desktopSwitchStep(1))
    #expect(rig.keys.calls == [.press(Key.rightArrow, arrowControl)])

    rig.dispatcher.ownAppFrontmost = false
    rig.keys.removeAll()
    rig.send(.tabSwitchStep(1), .zoomStep(1), .undoRedoStep(-1))
    #expect(rig.keys.calls == [
        .press(Key.tab, .maskControl), .press(Key.equal, .maskCommand), .press(Key.zKey, .maskCommand)
    ])
}

@Test func keyboardStepsPlayTheirStepHaptics() {
    let rig = Rig()
    rig.send(.haptic(.start), .zoomStep(1), .haptic(.step), .zoomStep(1), .haptic(.step))
    #expect(rig.haptics.calls.map(\.event) == [.start, .step, .step])
    #expect(rig.media.calls.isEmpty)
}

@Test func keyCornerActionsPressTheirShortcuts() {
    let rig = Rig()
    rig.send(.spotlight)
    rig.send(.lockScreen)
    rig.send(.screenshotArea)
    #expect(rig.keys.calls == [
        .press(Key.space, .maskCommand),
        .press(Key.qKey, [.maskControl, .maskCommand]),
        .press(Key.four, [.maskCommand, .maskShift])
    ])
    #expect(rig.missionControl.opened.isEmpty)
}

@Test func playPauseCornerPostsThePlayKey() {
    let rig = Rig()
    rig.send(.mediaPlayPause)
    #expect(rig.media.calls == [FakeMediaKeys.Call(key: .play, fine: false)])
}

@Test func missionControlCornersOpenTheirViews() {
    let rig = Rig()
    rig.send(.missionControl, .appWindows, .showDesktop)
    #expect(rig.missionControl.opened == [.all, .appWindows, .desktop])
    #expect(rig.keys.calls.isEmpty)
}

@Test func missionControlViewsUseTheirLaunchArguments() {
    #expect(MissionControlView.all.arguments.isEmpty)
    #expect(MissionControlView.appWindows.arguments == ["2"])
    #expect(MissionControlView.desktop.arguments == ["1"])
}

@Test func missionControlWithoutAPortDoesNothing() {
    let rig = Rig(withMissionControl: false)
    rig.send(.missionControl, .appWindows, .showDesktop)
    #expect(rig.keys.calls.isEmpty)
    #expect(rig.media.calls.isEmpty)
}

// MARK: - Engine to dispatcher on the side edges

/// A side edge set to the app switcher or the keyboard backlight behaves as on the top or bottom edge.
private func drive(_ engine: GestureEngine, from: Float, to: Float, x: Float, startT: Double) -> Double {
    let geometry = DeviceGeometry(widthMM: 120, heightMM: 80, isBuiltIn: true)
    var t = startT
    let steps = Int(abs(to - from))
    for index in 0 ... steps {
        let y = from + (to > from ? 1 : -1) * Float(index)
        var touches = TouchBuffer()
        touches.append(Touch(id: 1, x: x / 120, y: y / 80, majorAxisMM: 8))
        engine.process(Frame(deviceID: 1, timestamp: t, geometry: geometry, touches: touches))
        t += 0.008
    }
    return t
}

private func lift(_ engine: GestureEngine, at t: Double) {
    let geometry = DeviceGeometry(widthMM: 120, heightMM: 80, isBuiltIn: true)
    engine.process(Frame(deviceID: 1, timestamp: t, geometry: geometry, touches: TouchBuffer()))
    engine.process(Frame(deviceID: 1, timestamp: t + 0.2, geometry: geometry, touches: TouchBuffer()))
}

@Test func appSwitcherOnTheLeftEdgeHoldsCommandUntilLift() {
    let rig = Rig()
    var config = EngineConfig()
    config.left = .switchApps
    let engine = GestureEngine(config: config, sink: rig.dispatcher)
    let t = drive(engine, from: 15, to: 39, x: 5, startT: 0)
    #expect(rig.keys.calls == [
        .modifierDown(Key.command, .maskCommand), .press(Key.tab, .maskCommand), .press(Key.tab, .maskCommand)
    ])
    lift(engine, at: t)
    #expect(rig.keys.calls.last == .modifierUp(Key.command))
    #expect(rig.keys.count(.modifierUp(Key.command)) == 1)
}

/// At the standard step and at the most sensitive one (0.6, as Very High sets it), one limit haptic, then silence.
@Test(arguments: [Float(1.0), Float(0.6)])
func backlightOnTheRightEdgeShowsTheOverlayAndTheLimit(multiplier: Float) {
    let rig = Rig()
    var config = EngineConfig()
    config.thresholds.stepMM *= multiplier
    config.right = .keyboardBacklight
    let engine = GestureEngine(config: config, sink: rig.dispatcher)
    // 8 steps of 1/16 take the backlight from 0.5 to 1; the next steps push against the top.
    _ = drive(engine, from: 15, to: 55, x: 115, startT: 0)
    #expect(rig.backlight.current == 1)
    #expect(rig.overlay.calls.allSatisfy { $0.kind == .keyboardBacklight })
    #expect(rig.overlay.calls.last?.level == 1)
    #expect(rig.haptics.calls.map(\.event).filter { $0 == .limit }.count == 1)
    // Only the 8 steps that moved the level play a step haptic; the steps pushed against the top play none.
    #expect(rig.backlight.steps.count == 8)
    #expect(rig.haptics.calls.map(\.event).filter { $0 == .step }.count == 8)
    #expect(rig.media.calls.isEmpty)
}
