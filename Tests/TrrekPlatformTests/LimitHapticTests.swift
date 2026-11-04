import CoreGraphics
import Foundation
import Testing
import TrrekEngine
import TrrekPlatform

/// One limit haptic at the end of a range, then silence until the direction reverses or a new slide starts.
private struct LimitRig {
    let media = FakeMediaKeys()
    let haptics = FakeHaptics()
    let overlay = FakeOverlay()
    let volume: FakeLevel
    let brightness: FakeLevel
    let backlight: FakeBacklight
    let port: FakeExternalBrightness
    let locator: FakeDisplayLocator
    let queue = DispatchQueue(label: "test.limit.ddc")
    let dispatcher: CommandDispatcher

    init(volume: Float? = 0.5, brightness: Float? = 0.5, backlight: Float = 0.5, external: Float = 0.5) {
        self.volume = FakeLevel(volume)
        self.brightness = FakeLevel(brightness)
        self.backlight = FakeBacklight(level: backlight)
        port = FakeExternalBrightness(externals: [2], level: external)
        let locator = FakeDisplayLocator(1)
        self.locator = locator
        dispatcher = CommandDispatcher(
            mediaKeys: media,
            keys: FakeKeys(),
            mouse: FakeMouse(),
            haptics: haptics,
            freezer: FakeFreezer(),
            backlight: self.backlight,
            overlay: overlay,
            externalBrightness: port,
            displayLocator: { locator.locate() },
            volumeLevel: self.volume,
            brightnessLevel: self.brightness,
            displayQueue: queue
        )
        dispatcher.externalBrightnessEnabled = true
    }

    /// Sends `commands` as the engine does and waits for the display queue.
    func send(_ commands: GestureCommand...) {
        for command in commands {
            dispatcher.handle(command, device: 1)
        }
        queue.sync {}
    }

    var events: [HapticEvent] {
        haptics.calls.map(\.event)
    }
}

@Test func volumeAtTheTopPlaysOneLimitThenNothing() {
    let rig = LimitRig(volume: 1)
    rig.send(.haptic(.start), .stepVolume(1, fine: false), .haptic(.step))
    #expect(rig.events == [.start, .limit])
    rig.send(.stepVolume(1, fine: false), .haptic(.step), .stepVolume(1, fine: true), .haptic(.step))
    #expect(rig.events == [.start, .limit])
    #expect(rig.media.calls.isEmpty)

    // Reversing moves the level and plays step haptics again.
    rig.send(.stepVolume(-1, fine: false), .haptic(.step))
    #expect(rig.media.calls == [FakeMediaKeys.Call(key: .soundDown, fine: false)])
    #expect(rig.events == [.start, .limit, .step])
    // Back at the top in the same slide: a new arrival plays the limit once more.
    rig.send(.stepVolume(1, fine: false), .haptic(.step))
    #expect(rig.events == [.start, .limit, .step, .limit])

    // A new slide starts over.
    rig.send(.haptic(.start), .stepVolume(1, fine: false), .haptic(.step))
    #expect(rig.events == [.start, .limit, .step, .limit, .start, .limit])
    #expect(rig.media.calls.count == 1)
}

@Test func volumeBelowTheTopStepsNormally() {
    let rig = LimitRig(volume: 0.998)
    rig.send(.haptic(.start), .stepVolume(1, fine: false), .haptic(.step))
    #expect(rig.media.calls == [FakeMediaKeys.Call(key: .soundUp, fine: false)])
    #expect(rig.events == [.start, .step])
}

@Test func unknownVolumeKeepsTheOldBehaviour() {
    // Muted, or no volume control: no level, so every step posts its key and plays its haptic.
    let rig = LimitRig(volume: nil)
    rig.send(.haptic(.start), .stepVolume(1, fine: false), .haptic(.step), .stepVolume(1, fine: false), .haptic(.step))
    #expect(rig.media.calls.count == 2)
    #expect(rig.events == [.start, .step, .step])
}

@Test func brightnessAtTheBottomPlaysOneLimitThenNothing() {
    let rig = LimitRig(brightness: 0)
    rig.send(.haptic(.start), .stepBrightness(-1, fine: false), .haptic(.step))
    rig.send(.stepBrightness(-1, fine: false), .haptic(.step))
    #expect(rig.events == [.start, .limit])
    #expect(rig.media.calls.isEmpty)

    rig.send(.stepBrightness(1, fine: false), .haptic(.step))
    #expect(rig.media.calls == [FakeMediaKeys.Call(key: .brightnessUp, fine: false)])
    #expect(rig.events == [.start, .limit, .step])

    rig.send(.haptic(.start), .stepBrightness(-1, fine: false), .haptic(.step))
    #expect(rig.events == [.start, .limit, .step, .start, .limit])
}

@Test func backlightAtTheTopPlaysOneLimitThenNothing() {
    let rig = LimitRig(backlight: 1)
    rig.send(.haptic(.start), .stepKeyboardBacklight(1, fine: false), .haptic(.step))
    rig.send(.stepKeyboardBacklight(1, fine: false), .haptic(.step))
    #expect(rig.events == [.start, .limit])
    #expect(rig.backlight.steps.isEmpty)
    // The overlay still shows the level.
    #expect(rig.overlay.calls.map(\.level) == [1, 1])

    rig.send(.stepKeyboardBacklight(-1, fine: false), .haptic(.step))
    #expect(rig.backlight.steps.count == 1)
    #expect(rig.events == [.start, .limit, .step])

    // A commit ends the slide too; the next slide plays the limit again.
    rig.send(.stepKeyboardBacklight(1, fine: false), .haptic(.step))
    rig.send(.freezeCursor(false), .haptic(.start), .stepKeyboardBacklight(1, fine: false), .haptic(.step))
    #expect(rig.events == [.start, .limit, .step, .step, .start, .limit])
}

@Test func externalDisplayPlaysOneLimitAtItsBound() {
    let rig = LimitRig(external: 0.9375)
    rig.locator.display = 2
    // This step reaches the top: its step haptic plays, then the display queue plays the limit.
    rig.send(.haptic(.start), .stepBrightness(1, fine: false), .haptic(.step))
    #expect(rig.events == [.start, .step, .limit])

    // Pushing on: no step haptic, no second limit; the overlay still shows the level.
    rig.send(.stepBrightness(1, fine: false), .haptic(.step))
    rig.send(.stepBrightness(1, fine: false), .haptic(.step))
    #expect(rig.events == [.start, .step, .limit])
    #expect(rig.overlay.calls.map(\.level) == [1, 1, 1])
    #expect(rig.media.calls.isEmpty)

    // A new slide plays the limit once more, without the step haptic.
    rig.send(.haptic(.start), .stepBrightness(1, fine: false), .haptic(.step))
    #expect(rig.events == [.start, .step, .limit, .start, .limit])

    // Reversing plays step haptics again.
    rig.send(.stepBrightness(-1, fine: false), .haptic(.step))
    #expect(rig.events == [.start, .step, .limit, .start, .limit, .step])
}

@Test func levelBounds() {
    #expect(LevelBounds.isAtBound(1, direction: 1))
    #expect(LevelBounds.isAtBound(0.9995, direction: 1))
    #expect(!LevelBounds.isAtBound(0.998, direction: 1))
    #expect(!LevelBounds.isAtBound(1, direction: -1))
    #expect(LevelBounds.isAtBound(0, direction: -1))
    #expect(!LevelBounds.isAtBound(0, direction: 1))
    #expect(!LevelBounds.isAtBound(0, direction: 0))
}
