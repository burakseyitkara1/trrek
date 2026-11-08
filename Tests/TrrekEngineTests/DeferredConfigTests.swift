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

@Test func pausingEndsTheSlideAndAppliesTheWaitingConfig() {
    let (engine, sink, fb) = makeEngine()
    let t = engine.drive(fb, id: 1, from: (30, 78), to: (54, 78), startT: 0)
    engine.updateWhenIdle(config: config(top: .switchTabs))
    engine.setPaused(true)
    engine.setPaused(false)
    sink.removeAll()
    engine.drive(fb, id: 2, from: (30, 78), to: (54, 78), startT: t + 1)
    #expect(sink.count(.tabSwitchStep(1)) == 2)
}
