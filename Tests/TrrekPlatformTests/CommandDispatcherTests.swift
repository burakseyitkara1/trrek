import CoreGraphics
import Foundation
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

@Test func backlightAtItsBoundDropsTheStepHapticOfThatStep() {
    // The engine sends each step's haptic right after the step; at a bound only the limit haptic plays.
    let rig = Rig(backlight: FakeBacklight(level: 1))
    rig.send(.stepKeyboardBacklight(1, fine: false), .haptic(.step))
    #expect(rig.haptics.calls.map(\.event) == [.limit])
    // Only that one step haptic is dropped.
    rig.send(.haptic(.step))
    #expect(rig.haptics.calls.map(\.event) == [.limit, .step])
}

@Test func backlightStepAwayFromTheBoundKeepsItsStepHaptic() {
    let rig = Rig(backlight: FakeBacklight(level: 0.5))
    rig.send(.stepKeyboardBacklight(1, fine: false), .haptic(.step))
    #expect(rig.haptics.calls.map(\.event) == [.step])
}

@Test func backlightLimitSuppressionEndsAtTheNextCommand() {
    // A step haptic that does not directly follow the bounded step is played.
    let rig = Rig(backlight: FakeBacklight(level: 0))
    rig.send(.stepKeyboardBacklight(-1, fine: false), .stepVolume(1, fine: false), .haptic(.step))
    #expect(rig.haptics.calls.map(\.event) == [.limit, .step])
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

@Test func scrubStepsPressArrowKeys() {
    let rig = Rig()
    rig.send(.scrubStep(1), .scrubStep(-1))
    #expect(rig.keys.calls == [.press(124, []), .press(123, [])])
}

@Test func scrubShowsCumulativeLabel() {
    let rig = Rig()
    rig.send(.scrubStep(1), .scrubStep(1), .scrubStep(1))
    #expect(rig.overlay.calls.last == FakeOverlay.Call(kind: .scrub, level: 0.5, label: "+15 s"))
    rig.send(.scrubStep(-1), .scrubStep(-1), .scrubStep(-1), .scrubStep(-1), .scrubStep(-1))
    #expect(rig.overlay.calls.last == FakeOverlay.Call(kind: .scrub, level: 0.5, label: "\u{2212}10 s"))
}

@Test func scrubCancelSendsNothing() {
    let rig = Rig()
    rig.send(.scrubStep(1))
    rig.keys.removeAll()
    rig.send(.scrubCancel)
    #expect(rig.keys.calls.isEmpty)
}

@Test func scrubCommitResetsCounter() {
    let rig = Rig()
    rig.send(.scrubStep(1), .scrubStep(1))
    rig.keys.removeAll()
    rig.send(.scrubCommit)
    #expect(rig.keys.calls.isEmpty)
    rig.send(.scrubStep(1))
    #expect(rig.overlay.calls.last?.label == "+5 s")
}

// MARK: - External brightness

private let builtIn: CGDirectDisplayID = 1
private let external: CGDirectDisplayID = 2

/// A dispatcher with an external brightness port, a movable pointer and its own display queue.
private struct BrightnessRig {
    let media = FakeMediaKeys()
    let overlay = FakeOverlay()
    let port: FakeExternalBrightness
    let locator: FakeDisplayLocator
    let queue = DispatchQueue(label: "test.ddc")
    let dispatcher: CommandDispatcher

    init(
        pointerOn display: CGDirectDisplayID?,
        enabled: Bool,
        level: Float = 0.5,
        delay: TimeInterval = 0,
        failing: Bool = false
    ) {
        port = FakeExternalBrightness(externals: [external], level: level, delay: delay, failing: failing)
        locator = FakeDisplayLocator(display)
        queue.setSpecific(key: port.queueKey, value: true)
        let locator = locator
        dispatcher = CommandDispatcher(
            mediaKeys: media,
            keys: FakeKeys(),
            mouse: FakeMouse(),
            haptics: FakeHaptics(),
            freezer: FakeFreezer(),
            backlight: nil,
            overlay: overlay,
            externalBrightness: port,
            displayLocator: { locator.locate() },
            displayQueue: queue
        )
        dispatcher.externalBrightnessEnabled = enabled
    }

    /// Sends `commands` and waits until the display queue has run the work they queued.
    func send(_ commands: GestureCommand...) {
        for command in commands {
            dispatcher.handle(command, device: 1)
        }
        queue.sync {}
    }
}

@Test func builtInScreenUsesMediaKeys() {
    let rig = BrightnessRig(pointerOn: builtIn, enabled: true)
    rig.send(.stepBrightness(1, fine: false), .stepBrightness(-1, fine: true))
    #expect(rig.media.calls == [
        FakeMediaKeys.Call(key: .brightnessUp, fine: false),
        FakeMediaKeys.Call(key: .brightnessDown, fine: true)
    ])
    #expect(rig.port.steps.isEmpty)
    #expect(rig.overlay.calls.isEmpty)

    // Without a display under the pointer the media key is the fallback too.
    let nowhere = BrightnessRig(pointerOn: nil, enabled: true)
    nowhere.send(.stepBrightness(1, fine: false))
    #expect(nowhere.media.calls == [FakeMediaKeys.Call(key: .brightnessUp, fine: false)])
    #expect(nowhere.port.steps.isEmpty)
}

@Test func externalScreenUsesDDCWhenEnabled() {
    let rig = BrightnessRig(pointerOn: external, enabled: true)
    rig.send(.stepBrightness(1, fine: false), .stepBrightness(-1, fine: true))
    #expect(rig.port.steps == [
        FakeExternalBrightness.Step(display: external, direction: 1, fine: false),
        FakeExternalBrightness.Step(display: external, direction: -1, fine: true)
    ])
    #expect(rig.port.stepsOnMarkedQueue == [true, true])
    #expect(rig.overlay.calls == [
        FakeOverlay.Call(kind: .externalBrightness, level: 0.5625, label: nil),
        FakeOverlay.Call(kind: .externalBrightness, level: 0.546875, label: nil)
    ])
    #expect(rig.media.calls.isEmpty)

    // The step follows the pointer: back on the built-in screen, the media key is used again.
    rig.locator.display = builtIn
    rig.send(.stepBrightness(1, fine: false))
    #expect(rig.port.steps.count == 2)
    #expect(rig.media.calls == [FakeMediaKeys.Call(key: .brightnessUp, fine: false)])
}

@Test func externalDisabledUsesMediaKeys() {
    let rig = BrightnessRig(pointerOn: external, enabled: false)
    rig.send(.stepBrightness(-1, fine: false))
    #expect(rig.media.calls == [FakeMediaKeys.Call(key: .brightnessDown, fine: false)])
    #expect(rig.port.steps.isEmpty)
    #expect(rig.overlay.calls.isEmpty)

    // Turning the setting on takes effect for the next step.
    rig.dispatcher.externalBrightnessEnabled = true
    #expect(rig.dispatcher.externalBrightnessEnabled)
    rig.send(.stepBrightness(-1, fine: false))
    #expect(rig.port.steps == [FakeExternalBrightness.Step(display: external, direction: -1, fine: false)])
    #expect(rig.media.calls.count == 1)
}

@Test func failedDDCShowsNoDDC() {
    let rig = BrightnessRig(pointerOn: external, enabled: true, failing: true)
    rig.send(.stepBrightness(1, fine: false))
    #expect(rig.port.steps.count == 1)
    #expect(rig.overlay.calls == [FakeOverlay.Call(kind: .externalBrightness, level: 0, label: "No DDC")])
    // A failed DDC step does not fall back to the media key, which would change the built-in display instead.
    #expect(rig.media.calls.isEmpty)
}

@Test func ddcWorkRunsOffTheFrameThread() {
    let rig = BrightnessRig(pointerOn: external, enabled: true, delay: 0.3)
    let clock = ContinuousClock()
    let start = clock.now
    rig.dispatcher.handle(.stepBrightness(1, fine: false), device: 1)
    rig.dispatcher.handle(.haptic(.step), device: 1)
    let elapsed = clock.now - start
    #expect(elapsed < .milliseconds(100))
    // The slow step is still running; nothing has been shown yet.
    #expect(rig.overlay.calls.isEmpty)

    rig.queue.sync {}
    #expect(rig.port.steps.count == 1)
    #expect(rig.port.stepsOnMarkedQueue == [true])
    #expect(rig.overlay.calls == [FakeOverlay.Call(kind: .externalBrightness, level: 0.5625, label: nil)])
}

@Test func fastStepsAreMergedWhileTheDisplayIsBusy() {
    let rig = BrightnessRig(pointerOn: external, enabled: true, level: 0, delay: 0.2)
    for _ in 0 ..< 10 {
        rig.dispatcher.handle(.stepBrightness(1, fine: false), device: 1)
    }
    rig.queue.sync {}
    let steps = rig.port.steps
    #expect(steps.count <= 2)
    #expect(steps.map(\.direction).reduce(0, +) == 10)
    #expect(steps.allSatisfy { $0.display == external && !$0.fine })
    #expect(rig.overlay.calls.last == FakeOverlay.Call(kind: .externalBrightness, level: 0.625, label: nil))
    #expect(rig.overlay.calls.count == steps.count)
    #expect(rig.media.calls.isEmpty)
}

@Test func mergedStepsKeepDirectionAndPrecisionApart() {
    let rig = BrightnessRig(pointerOn: external, enabled: true, level: 0.5, delay: 0.2)
    // The first step occupies the display; the rest wait and are merged while they keep their precision.
    rig.dispatcher.handle(.stepBrightness(1, fine: false), device: 1)
    Thread.sleep(forTimeInterval: 0.05)
    for direction in [1, 1, -1, -1, -1] {
        rig.dispatcher.handle(.stepBrightness(direction, fine: false), device: 1)
    }
    rig.dispatcher.handle(.stepBrightness(1, fine: true), device: 1)
    rig.dispatcher.handle(.stepBrightness(1, fine: true), device: 1)
    rig.queue.sync {}
    #expect(rig.port.steps == [
        FakeExternalBrightness.Step(display: external, direction: 1, fine: false),
        // Reversing within the merged step nets out instead of moving on the old way.
        FakeExternalBrightness.Step(display: external, direction: -1, fine: false),
        FakeExternalBrightness.Step(display: external, direction: 2, fine: true)
    ])
    #expect(rig.overlay.calls.last?.level == 0.53125)
}
