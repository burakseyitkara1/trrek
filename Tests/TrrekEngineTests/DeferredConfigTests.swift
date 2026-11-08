import Foundation
import Testing
@testable import TrrekEngine

// A configuration change that waits for the gesture in progress (per-app edges switching with the front app).

private func config(top: EdgeAction) -> EngineConfig {
    var config = EngineConfig()
    config.top = top
    return config
}

// MARK: - The decision

@Test func busyStatesAreCandidatesAndSlides() {
    #expect(DeferredConfig.isBusy(.candidate))
    #expect(DeferredConfig.isBusy(.sliding))
    #expect(DeferredConfig.isBusy(.lost))
    #expect(!DeferredConfig.isBusy(.idle))
    #expect(!DeferredConfig.isBusy(.spent))
    #expect(!DeferredConfig.isBusy(.threeFinger))
}

@Test func requestWhileFreeAppliesAtOnce() {
    var deferred = DeferredConfig()
    let new = config(top: .switchTabs)
    #expect(deferred.request(new, current: EngineConfig(), busy: false) == new)
    #expect(deferred.pending == nil)
}

@Test func requestWhileBusyWaitsForTheEnd() {
    var deferred = DeferredConfig()
    let new = config(top: .switchTabs)
    #expect(deferred.request(new, current: EngineConfig(), busy: true) == nil)
    #expect(deferred.pending == new)
    #expect(deferred.settle(busy: true) == nil)
    #expect(deferred.pending == new)
    #expect(deferred.settle(busy: false) == new)
    #expect(deferred.pending == nil)
    #expect(deferred.settle(busy: false) == nil)
}

@Test func laterRequestReplacesTheWaitingOne() {
    var deferred = DeferredConfig()
    _ = deferred.request(config(top: .switchTabs), current: EngineConfig(), busy: true)
    _ = deferred.request(config(top: .zoom), current: EngineConfig(), busy: true)
    #expect(deferred.settle(busy: false) == config(top: .zoom))
}

@Test func requestingTheCurrentConfigDropsTheWaitingOne() {
    var deferred = DeferredConfig()
    _ = deferred.request(config(top: .switchTabs), current: EngineConfig(), busy: true)
    // Back to the app the slide started in: nothing changes, now or later.
    #expect(deferred.request(EngineConfig(), current: EngineConfig(), busy: true) == nil)
    #expect(deferred.pending == nil)
    #expect(deferred.request(EngineConfig(), current: EngineConfig(), busy: false) == nil)
}

@Test func cancelDropsTheWaitingConfig() {
    var deferred = DeferredConfig()
    _ = deferred.request(config(top: .switchTabs), current: EngineConfig(), busy: true)
    deferred.cancel()
    #expect(deferred.settle(busy: false) == nil)
}

// MARK: - The engine

/// Top edge on Switch Desktops, as when a slide moves to another desktop and so changes the front app.
private func makeEngine() -> (GestureEngine, RecordingSink, FrameBuilder) { // swiftlint:disable:this large_tuple
    let sink = RecordingSink()
    return (GestureEngine(config: config(top: .switchDesktops), sink: sink), sink, FrameBuilder())
}

@Test func slideKeepsItsActionWhenTheConfigChangesMidSlide() {
    let (engine, sink, fb) = makeEngine()
    var t = engine.drive(fb, id: 1, from: (30, 78), to: (54, 78), startT: 0)
    #expect(engine.stateKind == .sliding)
    #expect(sink.count(.desktopSwitchStep(1)) == 1)

    engine.updateWhenIdle(config: config(top: .switchTabs))
    #expect(engine.stateKind == .sliding)
    #expect(sink.count(.freezeCursor(false)) == 0)

    t = engine.drive(fb, id: 1, from: (54, 78), to: (94, 78), startT: t + 0.008)
    #expect(sink.count(.desktopSwitchStep(1)) == 3)
    #expect(sink.count(.tabSwitchStep(1)) == 0)

    // Lift; the slide ends after the lost timeout and the new configuration applies.
    engine.process(fb.frame(t: t + 0.008, []))
    #expect(engine.stateKind == .lost)
    engine.tick(now: t + 0.3)
    #expect(engine.stateKind == .idle)
    #expect(sink.count(.freezeCursor(false)) == 1)

    sink.removeAll()
    engine.drive(fb, id: 2, from: (30, 78), to: (54, 78), startT: t + 1)
    #expect(sink.count(.tabSwitchStep(1)) == 2)
    #expect(sink.count(.desktopSwitchStep(1)) == 0)
}

@Test func candidateKeepsTheConfigItLandedWith() {
    let (engine, sink, fb) = makeEngine()
    engine.process(fb.frame(t: 0, [(1, 30, 78)]))
    #expect(engine.stateKind == .candidate)
    engine.updateWhenIdle(config: config(top: .switchTabs))
    #expect(engine.stateKind == .candidate)

    engine.drive(fb, id: 1, from: (30, 78), to: (54, 78), startT: 0.008)
    #expect(engine.stateKind == .sliding)
    #expect(sink.count(.desktopSwitchStep(1)) == 1)
    #expect(sink.count(.tabSwitchStep(1)) == 0)
}

@Test func waitingConfigAppliesBeforeTheNextFingerLands() {
    let (engine, sink, fb) = makeEngine()
    var t = engine.drive(fb, id: 1, from: (30, 78), to: (54, 78), startT: 0)
    engine.updateWhenIdle(config: config(top: .switchTabs))
    // Lifted, and a new finger lands after the timeout with no tick in between.
    t += 0.008
    engine.process(fb.frame(t: t, []))
    sink.removeAll()
    engine.drive(fb, id: 2, from: (30, 78), to: (54, 78), startT: t + 0.3)
    #expect(sink.count(.tabSwitchStep(1)) == 2)
    #expect(sink.count(.desktopSwitchStep(1)) == 0)
}

@Test func configAppliesAtOnceWhileIdle() {
    let (engine, sink, fb) = makeEngine()
    engine.updateWhenIdle(config: config(top: .switchTabs))
    engine.drive(fb, id: 1, from: (30, 78), to: (54, 78), startT: 0)
    #expect(sink.count(.tabSwitchStep(1)) == 2)
}

@Test func sameConfigMidSlideChangesNothing() {
    let (engine, sink, fb) = makeEngine()
    engine.drive(fb, id: 1, from: (30, 78), to: (54, 78), startT: 0)
    engine.updateWhenIdle(config: config(top: .switchDesktops))
    #expect(engine.stateKind == .sliding)
    #expect(sink.count(.freezeCursor(false)) == 0)
    #expect(pending(engine) == nil)
}

@Test func directUpdateStillCommitsAndDropsTheWaitingConfig() {
    let (engine, sink, fb) = makeEngine()
    let t = engine.drive(fb, id: 1, from: (30, 78), to: (54, 78), startT: 0)
    engine.updateWhenIdle(config: config(top: .switchTabs))
    engine.update(config: config(top: .zoom))
    #expect(engine.stateKind == .idle)
    #expect(sink.count(.freezeCursor(false)) == 1)

    sink.removeAll()
    engine.drive(fb, id: 2, from: (30, 78), to: (54, 78), startT: t + 1)
    #expect(sink.count(.zoomStep(1)) > 0)
    #expect(sink.count(.tabSwitchStep(1)) == 0)
}

// MARK: - Each path that ends a gesture settles at once

/// The waiting configuration and the one in use, read under the engine's lock without sending a frame.
private func pending(_ engine: GestureEngine) -> EngineConfig? {
    engine.lock.withLock { engine.deferredConfig.pending }
}

private func current(_ engine: GestureEngine) -> EngineConfig {
    engine.lock.withLock { engine.config }
}

/// A slide on the top edge with Switch Tabs waiting; returns the time of its last frame.
private func slideWithWaitingConfig(_ engine: GestureEngine, _ fb: FrameBuilder) -> TimeInterval {
    let t = engine.drive(fb, id: 1, from: (30, 78), to: (54, 78), startT: 0)
    engine.updateWhenIdle(config: config(top: .switchTabs))
    #expect(pending(engine) == config(top: .switchTabs))
    #expect(current(engine) == config(top: .switchDesktops))
    return t
}

@Test func pausingSettlesAtOnce() {
    let (engine, _, fb) = makeEngine()
    _ = slideWithWaitingConfig(engine, fb)
    engine.setPaused(true)
    #expect(pending(engine) == nil)
    #expect(current(engine) == config(top: .switchTabs))
}

@Test func releasingTheHoldKeySettlesAtOnce() {
    var held = config(top: .switchDesktops)
    held.holdKeyRequired = true
    let sink = RecordingSink()
    let engine = GestureEngine(config: held, sink: sink)
    engine.setHoldKeySatisfied(true)
    engine.drive(FrameBuilder(), id: 1, from: (30, 78), to: (54, 78), startT: 0)
    var new = config(top: .switchTabs)
    new.holdKeyRequired = true
    engine.updateWhenIdle(config: new)
    #expect(pending(engine) == new)
    engine.setHoldKeySatisfied(false)
    #expect(engine.stateKind == .idle)
    #expect(pending(engine) == nil)
    #expect(current(engine) == new)
}

@Test func resetSettlesAtOnce() {
    let (engine, _, fb) = makeEngine()
    _ = slideWithWaitingConfig(engine, fb)
    engine.reset()
    #expect(pending(engine) == nil)
    #expect(current(engine) == config(top: .switchTabs))
}

@Test func watchdogTickSettlesAtOnce() {
    let (engine, _, fb) = makeEngine()
    let t = slideWithWaitingConfig(engine, fb)
    engine.process(fb.frame(t: t + 0.008, []))
    #expect(engine.stateKind == .lost)
    #expect(pending(engine) != nil)
    engine.tick(now: t + 0.3)
    #expect(pending(engine) == nil)
    #expect(current(engine) == config(top: .switchTabs))
}

@Test func secondFingerEndingTheSlideSettlesOnThatFrame() {
    let (engine, _, fb) = makeEngine()
    let t = slideWithWaitingConfig(engine, fb)
    engine.process(fb.frame(t: t + 0.008, [(1, 54, 78), (2, 60, 40)]))
    #expect(engine.stateKind == .spent)
    #expect(pending(engine) == nil)
    #expect(current(engine) == config(top: .switchTabs))
}

@Test func perpendicularAbortSettlesOnThatFrame() {
    let (engine, _, fb) = makeEngine()
    engine.process(fb.frame(t: 0, [(1, 30, 78)]))
    engine.updateWhenIdle(config: config(top: .switchTabs))
    #expect(pending(engine) != nil)
    engine.process(fb.frame(t: 0.008, [(1, 30, 72)]))
    #expect(engine.stateKind == .spent)
    #expect(pending(engine) == nil)
    #expect(current(engine) == config(top: .switchTabs))
}

@Test func framesFromAnotherDeviceDoNotSettle() {
    let (engine, _, fb) = makeEngine()
    let t = slideWithWaitingConfig(engine, fb)
    var other = FrameBuilder()
    other.deviceID = 2
    engine.process(other.frame(t: t + 0.008, []))
    engine.process(other.frame(t: t + 0.016, [(5, 60, 40)]))
    #expect(engine.stateKind == .sliding)
    #expect(pending(engine) == config(top: .switchTabs))
    #expect(current(engine) == config(top: .switchDesktops))
}

// MARK: - Double taps across a change of the front app

/// One finger down at `t` on (`xMM`, `yMM`) and lifted 0.1 s later; returns the lift time.
@discardableResult
private func tap(_ engine: GestureEngine, _ fb: FrameBuilder, at position: (Float, Float), t: Double) -> Double {
    engine.process(fb.frame(t: t, [(1, position.0, position.1)]))
    engine.process(fb.frame(t: t + 0.1, []))
    return t + 0.1
}

private func cornerConfig(top: EdgeAction) -> EngineConfig {
    var config = config(top: top)
    config.bottomRight = .mute
    return config
}

@Test func cornerDoubleTapSurvivesAFrontAppChangeBetweenTheTaps() {
    let sink = RecordingSink()
    let engine = GestureEngine(config: cornerConfig(top: .switchApps), sink: sink)
    let fb = FrameBuilder()
    let lift = tap(engine, fb, at: (115, 5), t: 0)
    // The first tap clicked another app to the front; its edges apply at once.
    engine.updateWhenIdle(config: cornerConfig(top: .switchTabs))
    #expect(current(engine) == cornerConfig(top: .switchTabs))
    tap(engine, fb, at: (115, 5), t: lift + 0.2)
    #expect(sink.commands == [.mute, .haptic(.tap)])
}

@Test func cornerDoubleTapSurvivesAChangeThatWaitedForTheFirstTap() {
    let sink = RecordingSink()
    let engine = GestureEngine(config: cornerConfig(top: .switchApps), sink: sink)
    let fb = FrameBuilder()
    engine.process(fb.frame(t: 0, [(1, 115, 5)]))
    #expect(engine.stateKind == .candidate)
    engine.updateWhenIdle(config: cornerConfig(top: .switchTabs))
    #expect(pending(engine) != nil)
    // The lift records the tap, then the waiting configuration settles.
    engine.process(fb.frame(t: 0.1, []))
    #expect(pending(engine) == nil)
    tap(engine, fb, at: (115, 5), t: 0.3)
    #expect(sink.commands == [.mute, .haptic(.tap)])
}

@Test func mediaEdgeTapIsKeptOnlyWhileTheEdgeStaysMedia() {
    var media = EngineConfig()
    media.bottom = .media
    var mediaOtherTop = media
    mediaOtherTop.top = .switchTabs
    var volume = EngineConfig()
    volume.bottom = .volume
    let fb = FrameBuilder()

    // Still media in the new configuration: the pair completes.
    let kept = RecordingSink()
    let keeping = GestureEngine(config: media, sink: kept)
    var lift = tap(keeping, fb, at: (60, 5), t: 0)
    keeping.updateWhenIdle(config: mediaOtherTop)
    tap(keeping, fb, at: (60, 5), t: lift + 0.2)
    #expect(kept.commands == [.mediaPlayPause, .haptic(.tap)])

    // The edge now changes the volume: the first tap means nothing any more.
    let dropped = RecordingSink()
    let dropping = GestureEngine(config: media, sink: dropped)
    lift = tap(dropping, fb, at: (60, 5), t: 0)
    dropping.updateWhenIdle(config: volume)
    tap(dropping, fb, at: (60, 5), t: lift + 0.2)
    #expect(dropped.commands.isEmpty)
}

@Test func cornerTapIsDroppedWhenTheCornerChanges() {
    let old = cornerConfig(top: .switchApps)
    var off = old
    off.top = .switchTabs
    off.bottomRight = .off
    #expect(!GestureEngine.tapSurvives((corner: .bottomRight, edge: nil, at: 0), from: old, to: off))
    #expect(GestureEngine.tapSurvives(
        (corner: .bottomRight, edge: nil, at: 0),
        from: old,
        to: cornerConfig(top: .zoom)
    ))
    var screenshot = old
    screenshot.bottomRight = .screenshot
    #expect(!GestureEngine.tapSurvives((corner: .bottomRight, edge: nil, at: 0), from: old, to: screenshot))
}

@Test func settingsChangeStillDropsThePendingTap() {
    let sink = RecordingSink()
    let engine = GestureEngine(config: cornerConfig(top: .switchApps), sink: sink)
    let fb = FrameBuilder()
    let lift = tap(engine, fb, at: (115, 5), t: 0)
    engine.update(config: cornerConfig(top: .switchTabs))
    tap(engine, fb, at: (115, 5), t: lift + 0.2)
    #expect(sink.commands.isEmpty)
}
