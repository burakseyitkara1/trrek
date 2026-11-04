import CoreGraphics
import Testing
import TrrekPlatform

// `#expect` cannot wrap a mutating call, so each change result goes through `changed` first.

@Test func noneIsAlwaysSatisfied() {
    var changed: Bool
    var tracker = HoldKeyTracker(key: .none, mode: .hold)
    #expect(tracker.isSatisfied)
    changed = tracker.handleFlagsChanged(.maskShift, at: 0)
    #expect(!changed)
    #expect(tracker.isSatisfied)
    changed = tracker.handleFlagsChanged([], at: 0.1)
    #expect(!changed)
    #expect(tracker.isSatisfied)
    tracker.handleKeyDown(at: 0.2)
    tracker.reset()
    #expect(tracker.isSatisfied)

    var toggle = HoldKeyTracker(key: .none, mode: .toggle)
    #expect(toggle.isSatisfied)
    changed = toggle.handleFlagsChanged(.maskCommand, at: 0)
    #expect(!changed)
    changed = toggle.handleFlagsChanged([], at: 0.1)
    #expect(!changed)
    #expect(toggle.isSatisfied)
}

@Test func holdFollowsModifierState() {
    var changed: Bool
    var tracker = HoldKeyTracker(key: .shift, mode: .hold)
    #expect(!tracker.isSatisfied)
    changed = tracker.handleFlagsChanged(.maskShift, at: 0)
    #expect(changed)
    #expect(tracker.isSatisfied)
    // Another modifier joining does not change the state.
    changed = tracker.handleFlagsChanged([.maskShift, .maskCommand], at: 0.1)
    #expect(!changed)
    #expect(tracker.isSatisfied)
    changed = tracker.handleFlagsChanged([], at: 0.2)
    #expect(changed)
    #expect(!tracker.isSatisfied)
    // A different modifier alone does not satisfy a shift tracker.
    changed = tracker.handleFlagsChanged(.maskControl, at: 0.3)
    #expect(!changed)
    #expect(!tracker.isSatisfied)
}

@Test func toggleFlipsOnLonePressRelease() {
    var changed: Bool
    var tracker = HoldKeyTracker(key: .option, mode: .toggle)
    #expect(!tracker.isSatisfied)
    changed = tracker.handleFlagsChanged(.maskAlternate, at: 0)
    #expect(!changed)
    #expect(!tracker.isSatisfied)
    changed = tracker.handleFlagsChanged([], at: 0.2)
    #expect(changed)
    #expect(tracker.isSatisfied)

    changed = tracker.handleFlagsChanged(.maskAlternate, at: 1.0)
    #expect(!changed)
    changed = tracker.handleFlagsChanged([], at: 1.2)
    #expect(changed)
    #expect(!tracker.isSatisfied)
}

@Test func toggleIgnoresSlowRelease() {
    var changed: Bool
    var tracker = HoldKeyTracker(key: .option, mode: .toggle)
    changed = tracker.handleFlagsChanged(.maskAlternate, at: 0)
    #expect(!changed)
    changed = tracker.handleFlagsChanged([], at: 0.5)
    #expect(!changed)
    #expect(!tracker.isSatisfied)
}

@Test func toggleIgnoresModifierUsedAsChord() {
    var changed: Bool
    var tracker = HoldKeyTracker(key: .command, mode: .toggle)
    changed = tracker.handleFlagsChanged(.maskCommand, at: 0)
    #expect(!changed)
    tracker.handleKeyDown(at: 0.1)
    changed = tracker.handleFlagsChanged([], at: 0.2)
    #expect(!changed)
    #expect(!tracker.isSatisfied)

    // Pressed while another modifier is already held: not a lone press either.
    changed = tracker.handleFlagsChanged(.maskShift, at: 1.0)
    #expect(!changed)
    changed = tracker.handleFlagsChanged([.maskShift, .maskCommand], at: 1.05)
    #expect(!changed)
    changed = tracker.handleFlagsChanged(.maskShift, at: 1.15)
    #expect(!changed)
    #expect(!tracker.isSatisfied)
}

@Test func resetClearsToggle() {
    var changed: Bool
    var tracker = HoldKeyTracker(key: .control, mode: .toggle)
    changed = tracker.handleFlagsChanged(.maskControl, at: 0)
    #expect(!changed)
    changed = tracker.handleFlagsChanged([], at: 0.1)
    #expect(changed)
    #expect(tracker.isSatisfied)
    tracker.reset()
    #expect(!tracker.isSatisfied)

    // A press in flight when reset happens does not toggle on release.
    changed = tracker.handleFlagsChanged(.maskControl, at: 1.0)
    #expect(!changed)
    tracker.reset()
    changed = tracker.handleFlagsChanged([], at: 1.1)
    #expect(!changed)
    #expect(!tracker.isSatisfied)
}

@Test func toggleIgnoresModifierClick() {
    var changed: Bool
    var tracker = HoldKeyTracker(key: .command, mode: .toggle)
    changed = tracker.handleFlagsChanged(.maskCommand, at: 0)
    #expect(!changed)
    // ⌘-click: a mouse button goes down while the key is held.
    tracker.handleMouseDown(at: 0.05)
    changed = tracker.handleFlagsChanged([], at: 0.1)
    #expect(!changed)
    #expect(!tracker.isSatisfied)

    // The next lone press still toggles.
    changed = tracker.handleFlagsChanged(.maskCommand, at: 1.0)
    #expect(!changed)
    changed = tracker.handleFlagsChanged([], at: 1.1)
    #expect(changed)
    #expect(tracker.isSatisfied)
}

@Test func toggleIgnoresPressJoinedByAnotherModifier() {
    var changed: Bool
    var tracker = HoldKeyTracker(key: .option, mode: .toggle)
    changed = tracker.handleFlagsChanged(.maskAlternate, at: 0)
    #expect(!changed)
    // Shift joins while Option is down, then both are released quickly.
    changed = tracker.handleFlagsChanged([.maskAlternate, .maskShift], at: 0.05)
    #expect(!changed)
    changed = tracker.handleFlagsChanged(.maskAlternate, at: 0.1)
    #expect(!changed)
    changed = tracker.handleFlagsChanged([], at: 0.15)
    #expect(!changed)
    #expect(!tracker.isSatisfied)
}

@Test func cancelPressKeepsTheToggleState() {
    var changed: Bool
    var tracker = HoldKeyTracker(key: .option, mode: .toggle)
    changed = tracker.handleFlagsChanged(.maskAlternate, at: 0)
    #expect(!changed)
    changed = tracker.handleFlagsChanged([], at: 0.1)
    #expect(changed)
    #expect(tracker.isSatisfied)

    // A press is in flight when the pipeline restarts; its key-up is missed.
    changed = tracker.handleFlagsChanged(.maskAlternate, at: 1.0)
    #expect(!changed)
    tracker.cancelPress()
    #expect(tracker.isSatisfied)

    // The next press starts afresh and toggles off.
    changed = tracker.handleFlagsChanged(.maskAlternate, at: 5.0)
    #expect(!changed)
    changed = tracker.handleFlagsChanged([], at: 5.1)
    #expect(changed)
    #expect(!tracker.isSatisfied)

    tracker.reset()
    #expect(!tracker.isSatisfied)
}
