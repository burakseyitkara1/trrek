import CoreGraphics
import Testing
import TrrekEngine
import TrrekPlatform

private struct Rig {
    let media = FakeMediaKeys()
    let keys = FakeKeys()
    let mouse = FakeMouse()
    let haptics = FakeHaptics()
    let freezer = FakeFreezer()
    let overlay = FakeOverlay()
    let backlight: FakeBacklight?
    let dispatcher: CommandDispatcher

    init(backlight: FakeBacklight? = nil, withOverlay: Bool = true) {
        self.backlight = backlight
        dispatcher = CommandDispatcher(
            mediaKeys: media,
            keys: keys,
            mouse: mouse,
            haptics: haptics,
            freezer: freezer,
            backlight: backlight,
            overlay: withOverlay ? overlay : nil
        )
    }

    func send(_ commands: GestureCommand...) {
        for command in commands {
            dispatcher.handle(command, device: 1)
        }
    }
}

private let command: CGKeyCode = 55
private let tab: CGKeyCode = 48
private let escape: CGKeyCode = 53

@Test func volumeStepsPostMediaKeys() {
    let rig = Rig()
    rig.send(.stepVolume(1, fine: false), .stepVolume(-1, fine: true))
    #expect(rig.media.calls == [
        FakeMediaKeys.Call(key: .soundUp, fine: false),
        FakeMediaKeys.Call(key: .soundDown, fine: true)
    ])
    rig.send(.stepBrightness(1, fine: false), .stepBrightness(-1, fine: false))
    #expect(Array(rig.media.calls.suffix(2)) == [
        FakeMediaKeys.Call(key: .brightnessUp, fine: false),
        FakeMediaKeys.Call(key: .brightnessDown, fine: false)
    ])
    #expect(rig.keys.calls.isEmpty)
}

@Test func switcherProtocol() {
    let rig = Rig()
    rig.send(.appSwitchStep(1))
    #expect(rig.keys.calls == [.modifierDown(command, .maskCommand), .press(tab, .maskCommand)])
    rig.keys.removeAll()
    rig.send(.appSwitchStep(-1))
    #expect(rig.keys.calls == [.press(tab, [.maskCommand, .maskShift])])
    rig.keys.removeAll()
    rig.send(.appSwitchCommit)
    #expect(rig.keys.calls == [.modifierUp(command)])
    rig.keys.removeAll()
    // A new gesture holds Command again.
    rig.send(.appSwitchStep(1))
    #expect(rig.keys.calls.first == .modifierDown(command, .maskCommand))
}

@Test func switcherCancelSendsEscapeThenReleases() {
    let rig = Rig()
    rig.send(.appSwitchStep(1), .appSwitchStep(1))
    rig.keys.removeAll()
    rig.send(.appSwitchCancel)
    #expect(rig.keys.calls == [.press(escape, .maskCommand), .modifierUp(command)])
    rig.keys.removeAll()
    rig.dispatcher.releaseAll()
    #expect(rig.keys.calls.isEmpty)
}

@Test func releaseAllReleasesHeldModifier() {
    let rig = Rig()
    rig.send(.freezeCursor(true), .appSwitchStep(1))
    rig.dispatcher.releaseAll()
    #expect(rig.keys.count(.modifierUp(command)) == 1)
    #expect(rig.freezer.last == false)
    rig.dispatcher.releaseAll()
    #expect(rig.keys.count(.modifierUp(command)) == 1)
    #expect(rig.freezer.last == false)
}

@Test func backlightStepShowsOverlay() {
    let rig = Rig(backlight: FakeBacklight(level: 0.5))
    rig.send(.stepKeyboardBacklight(1, fine: false))
    #expect(rig.backlight?.steps.count == 1)
    #expect(rig.backlight?.steps.first?.direction == 1)
    #expect(rig.backlight?.steps.first?.fine == false)
    #expect(rig.overlay.calls == [FakeOverlay.Call(kind: .keyboardBacklight, level: 0.5625, label: nil)])
    #expect(rig.media.calls.isEmpty)
}

@Test func backlightAtItsBoundsPlaysTheLimitHaptic() {
    let rig = Rig(backlight: FakeBacklight(level: 1))
    rig.dispatcher.hapticStrength = .light
    rig.send(.stepKeyboardBacklight(1, fine: false))
    #expect(rig.haptics.calls == [FakeHaptics.Call(event: .limit, strength: .light)])
    #expect(rig.overlay.calls.last?.level == 1)

    let low = Rig(backlight: FakeBacklight(level: 0))
    low.send(.stepKeyboardBacklight(-1, fine: true))
    #expect(low.haptics.calls == [FakeHaptics.Call(event: .limit, strength: .medium)])
}

@Test func backlightReachingABoundPlaysNoLimitHaptic() {
    // The step that arrives at the bound still moved the level; only the next one hits the limit.
    let rig = Rig(backlight: FakeBacklight(level: 0.9375))
    rig.send(.stepKeyboardBacklight(1, fine: false))
    #expect(rig.backlight?.current == 1)
    #expect(rig.haptics.calls.isEmpty)
    rig.send(.stepKeyboardBacklight(1, fine: false))
    #expect(rig.haptics.calls.map(\.event) == [.limit])
    // Moving away from the bound is an ordinary step.
    rig.send(.stepKeyboardBacklight(-1, fine: false))
    #expect(rig.haptics.calls.count == 1)
}

@Test func backlightLimitHapticRespectsOff() {
    let rig = Rig(backlight: FakeBacklight(level: 1))
    rig.dispatcher.hapticStrength = .off
    rig.send(.stepKeyboardBacklight(1, fine: false))
    #expect(rig.haptics.calls.isEmpty)
}

@Test func backlightMissingDoesNothing() {
    let rig = Rig(backlight: nil)
    rig.send(.stepKeyboardBacklight(1, fine: false), .stepKeyboardBacklight(-1, fine: true))
    #expect(rig.overlay.calls.isEmpty)
    #expect(rig.media.calls.isEmpty)
    #expect(rig.keys.calls.isEmpty)
}

@Test func hapticsOffPerformsNothing() {
    let rig = Rig()
    rig.dispatcher.hapticStrength = .off
    rig.send(.haptic(.step), .haptic(.start), .haptic(.tap), .haptic(.limit))
    #expect(rig.haptics.calls.isEmpty)
}

@Test func hapticsForwardEventWithStrength() {
    let rig = Rig()
    rig.dispatcher.hapticStrength = .medium
    rig.send(.haptic(.step))
    #expect(rig.haptics.calls == [FakeHaptics.Call(event: .step, strength: .medium)])
    rig.dispatcher.hapticStrength = .strong
    rig.send(.haptic(.start))
    #expect(rig.haptics.calls.last == FakeHaptics.Call(event: .start, strength: .strong))
}

@Test func cornerAndMediaCommands() {
    let rig = Rig()
    rig.send(.mute, .screenshot, .mediaNext, .middleClick)
    #expect(rig.media.calls == [
        FakeMediaKeys.Call(key: .mute, fine: false),
        FakeMediaKeys.Call(key: .next, fine: false)
    ])
    #expect(rig.keys.calls == [.press(23, [.maskCommand, .maskShift])])
    #expect(rig.mouse.middleClicks == 1)
    rig.send(.mediaPlayPause, .mediaPrevious)
    #expect(Array(rig.media.calls.suffix(2)) == [
        FakeMediaKeys.Call(key: .play, fine: false),
        FakeMediaKeys.Call(key: .previous, fine: false)
    ])
}

@Test func freezeCommandsForward() {
    let rig = Rig()
    rig.send(.freezeCursor(true), .freezeCursor(false))
    #expect(rig.freezer.calls == [true, false])
}

@Test func scrubCommandsAreIgnored() {
    let rig = Rig()
    rig.send(.scrubStep(1), .scrubCommit, .scrubCancel)
    #expect(rig.media.calls.isEmpty)
    #expect(rig.keys.calls.isEmpty)
    #expect(rig.mouse.middleClicks == 0)
}
