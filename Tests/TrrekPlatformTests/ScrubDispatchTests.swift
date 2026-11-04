import CoreGraphics
import Testing
import TrrekEngine
import TrrekPlatform

/// A dispatcher with only the ports scrub uses.
private struct ScrubRig {
    let keys = FakeKeys()
    let overlay = FakeOverlay()
    let dispatcher: CommandDispatcher

    init() {
        dispatcher = CommandDispatcher(
            mediaKeys: FakeMediaKeys(),
            keys: keys,
            mouse: FakeMouse(),
            haptics: FakeHaptics(),
            freezer: FakeFreezer(),
            backlight: nil,
            overlay: overlay
        )
    }

    func send(_ commands: GestureCommand...) {
        for command in commands {
            dispatcher.handle(command, device: 1)
        }
    }
}

@Test func scrubStepsPressArrowKeys() {
    let rig = ScrubRig()
    rig.send(.scrubStep(1), .scrubStep(-1))
    #expect(rig.keys.calls == [.press(124, []), .press(123, [])])
}

@Test func scrubShowsCumulativeLabel() {
    let rig = ScrubRig()
    rig.send(.scrubStep(1), .scrubStep(1), .scrubStep(1))
    #expect(rig.overlay.calls.last == FakeOverlay.Call(kind: .scrub, level: 0.5, label: "+15 s"))
    rig.send(.scrubStep(-1), .scrubStep(-1), .scrubStep(-1), .scrubStep(-1), .scrubStep(-1))
    #expect(rig.overlay.calls.last == FakeOverlay.Call(kind: .scrub, level: 0.5, label: "\u{2212}10 s"))
}

@Test func scrubCancelSendsNothing() {
    let rig = ScrubRig()
    rig.send(.scrubStep(1))
    rig.keys.removeAll()
    rig.send(.scrubCancel)
    #expect(rig.keys.calls.isEmpty)
}

@Test func scrubCommitResetsCounter() {
    let rig = ScrubRig()
    rig.send(.scrubStep(1), .scrubStep(1))
    rig.keys.removeAll()
    rig.send(.scrubCommit)
    #expect(rig.keys.calls.isEmpty)
    rig.send(.scrubStep(1))
    #expect(rig.overlay.calls.last?.label == "+5 s")
}

@Test func scrubSendsNoKeysWhileTrrekIsFrontmost() {
    let rig = ScrubRig()
    rig.dispatcher.ownAppFrontmost = true
    #expect(rig.dispatcher.ownAppFrontmost)
    rig.send(.scrubStep(1), .scrubStep(-1), .scrubStep(1))
    #expect(rig.keys.calls.isEmpty)
    #expect(rig.overlay.calls.isEmpty)
    rig.send(.scrubCommit)

    // Another app in front again: steps count from zero.
    rig.dispatcher.ownAppFrontmost = false
    rig.send(.scrubStep(1))
    #expect(rig.keys.calls == [.press(124, [])])
    #expect(rig.overlay.calls == [FakeOverlay.Call(kind: .scrub, level: 0.5, label: "+5 s")])
}
