import Foundation
import os

public enum StateKind: Sendable, Equatable {
    case idle, candidate, sliding, lost, spent, threeFinger
}

/// Turns multitouch frames into gesture commands.
///
/// Thread-safe: every public method (`process`, `tick`, `update`, the host signals, `reset` and `stateKind`)
/// runs under the engine's own unfair lock, so calls from the frame thread and from the main thread are
/// serialized. That lock is what makes the `@unchecked Sendable` conformance sound. A host may also wrap the
/// calls in a lock of its own; the engine never takes that one.
///
/// `CommandSink.handle` is invoked synchronously while the lock is held. The sink must not call back into
/// the engine (the lock is not recursive, so doing so deadlocks).
///
/// All times are seconds of system uptime (`ProcessInfo.processInfo.systemUptime`), the clock of
/// `Frame.timestamp`. The engine never allocates on the heap while handling a frame.
///
/// The sink is held weakly so that the engine never keeps its owner alive; commands emitted after the sink
/// has gone away are dropped.
public final class GestureEngine: @unchecked Sendable {
    /// How a slide ends. Internal rather than private so the gates in `GestureEngine+Gates.swift` reach it.
    enum Outcome {
        case commit, cancel
    }

    /// Absorbs float rounding when converting normalized positions to mm, so an exact multiple of the
    /// step distance always yields that many steps.
    private static let stepToleranceMM: Float = 0.001

    /// The most step commands one frame can emit. A real finger moves a few steps per frame at most; the cap
    /// only bounds the work for a corrupt coordinate (say 1e9) whose remainder would otherwise never shrink.
    /// When the cap is hit, the rest of the accumulator is dropped, so a garbage coordinate cannot keep
    /// emitting steps on the frames that follow.
    static let maxStepsPerFrame = 64

    /// Serializes every public entry point. Allocated once with the engine, never per frame.
    private let lock = OSAllocatedUnfairLock()
    private weak var sink: CommandSink?
    // Internal rather than private so the tap and three-finger handlers in `GestureEngine+Taps.swift` reach them.
    var config: EngineConfig
    var state: EngineState = .idle
    private var activeDeviceID: UInt64 = 0
    /// The previous single tap on a corner or a media edge, waiting for its second tap.
    var lastTap: TapRecord?

    // Host signals, set through the public API and read by the gates in `GestureEngine+Gates.swift`.
    var lastKeyDown: TimeInterval = -.infinity
    var holdKeySatisfied = false
    var paused = false

    public init(config: EngineConfig, sink: CommandSink) {
        self.config = config
        self.sink = sink
    }

    // MARK: - States

    private func handleIdle(_ frame: Frame) {
        let touches = frame.touches
        guard touches.count >= 1 else { return }
        activeDeviceID = frame.deviceID
        guard admitsNewGesture(at: frame.timestamp) else {
            enterSpent(firstDownTime: Self.blockedDownTime, start: touches)
            return
        }
        let touch = touches[0]
        let zone = touches.count == 1 ? Geometry.zone(of: touch, in: frame.geometry, config: config) : .none
        if zone == .none {
            // Every touch is new here, so three of them landing together may arm a middle click.
            handleSpent(firstDownTime: frame.timestamp, start: TouchBuffer(), frame)
        } else {
            state = .candidate(CandidateData(
                zone: zone,
                touchID: touch.id,
                x0: touch.x,
                y0: touch.y,
                t0: frame.timestamp
            ))
        }
    }

    private func handleCandidate(_ data: CandidateData, _ frame: Frame) {
        let touches = frame.touches
        let origin = data.origin
        guard admitsNewGesture(at: frame.timestamp) else {
            // No slide and no tap; the fingers wait in `spent` until they all lift.
            spend(firstDownTime: Self.blockedDownTime, origin: origin, frame)
            return
        }
        if touches.count >= 2 {
            // The candidate finger keeps its landing position; the new fingers join `spent` as they are now,
            // and the three-finger rule applies on this same frame.
            spend(firstDownTime: data.t0, origin: origin, frame)
            return
        }
        guard let touch = touches.touch(id: data.touchID) else {
            // Lift; a different finger starts over from idle on the same frame.
            recognizeTap(data, liftTime: frame.timestamp)
            state = .idle
            handleIdle(frame)
            return
        }
        guard let edge = Geometry.slideEdge(for: data.zone, from: origin, to: touch, in: frame.geometry) else {
            spend(firstDownTime: data.t0, origin: origin, frame)
            return
        }
        let delta = Geometry.deltaMM(edge: edge, from: origin, to: touch, in: frame.geometry)
        let thresholds = config.thresholds
        if abs(delta.along) >= thresholds.slideStartMM {
            let action = config.action(for: edge)
            // With `bottomQuarterOnly`, a corner above the bottom quarter only slides along its horizontal edge.
            let verticalBlocked = config.bottomQuarterOnly && data.y0 >= Geometry.bottomQuarter
                && (edge == .left || edge == .right)
            guard action != .off, !verticalBlocked else {
                spend(firstDownTime: data.t0, origin: origin, frame)
                return
            }
            startSlide(from: data, edge: edge, action: action, touch: touch, frame: frame)
        } else if abs(delta.perpendicular) >= thresholds.abortPerpendicularMM {
            spend(firstDownTime: data.t0, origin: origin, frame)
        } else {
            var updated = data
            updated.maxMoveMM = max(data.maxMoveMM, Self.axisMoveMM(from: origin, to: touch, in: frame.geometry))
            state = .candidate(updated)
        }
    }

    private func handleSliding(_ data: SlideData, _ frame: Frame) {
        if frame.touches.count >= 2 {
            finish(data, .cancel)
            // Seeded with the landing point, so the slide's own movement rules out a middle click.
            spend(firstDownTime: data.firstDownTime, origin: data.origin, frame)
            return
        }
        guard let touch = frame.touches.touch(id: data.touchID) else {
            var stale = data
            stale.lastFrameTime = frame.timestamp
            state = .lost(stale, since: frame.timestamp)
            return
        }
        var slide = data
        let delta = Geometry.deltaMM(edge: slide.edge, from: slide.previous, to: touch, in: frame.geometry)
        slide.accumulatedMM += delta.along
        slide.previous = touch
        slide.lastFrameTime = frame.timestamp
        guard emitSteps(&slide) else {
            abandon(slide, frame)
            return
        }
        state = .sliding(slide)
    }

    private func handleLost(_ data: SlideData, since: TimeInterval, _ frame: Frame) {
        if frame.timestamp - since >= config.thresholds.lostTimeout {
            finish(data, .commit)
            state = .idle
            handleIdle(frame)
            return
        }
        guard let touch = frame.touches.touch(id: data.touchID) else { return }
        // The finger is back: resume from where it is now so the gap does not count as movement.
        var slide = data
        slide.previous = touch
        handleSliding(slide, frame)
    }

    // MARK: - Slides

    private func startSlide(from candidate: CandidateData, edge: Edge, action: EdgeAction, touch: Touch, frame: Frame) {
        lastTap = nil
        let origin = candidate.origin
        let alongMM = Geometry.deltaMM(edge: edge, from: origin, to: touch, in: frame.geometry).along
        let frozen = config.freezeCursor
        if frozen {
            emit(.freezeCursor(true))
        }
        emit(.haptic(.start))
        var slide = SlideData(
            edge: edge,
            action: action,
            firstDownTime: candidate.t0,
            origin: origin,
            touchID: touch.id,
            previous: touch,
            accumulatedMM: alongMM,
            stepsEmitted: 0,
            lastFrameTime: frame.timestamp,
            frozen: frozen
        )
        guard emitSteps(&slide) else {
            abandon(slide, frame)
            return
        }
        state = .sliding(slide)
    }

    /// Turns the accumulated distance into step commands, at most `maxStepsPerFrame` of them. Returns `false`
    /// without emitting anything when the accumulator is not finite: the accumulator starts finite, so a
    /// non-finite one means this frame's movement came from a non-finite (corrupt) coordinate.
    private func emitSteps(_ slide: inout SlideData) -> Bool {
        guard slide.accumulatedMM.isFinite else { return false }
        let step = Geometry.stepMM(for: slide.action, thresholds: config.thresholds)
        // A step at or below the tolerance would never shrink the remainder below the threshold.
        guard step.isFinite, step > Self.stepToleranceMM else { return true }
        let threshold = step - Self.stepToleranceMM
        for _ in 0 ..< Self.maxStepsPerFrame {
            guard abs(slide.accumulatedMM) >= threshold else { break }
            let sign = slide.accumulatedMM > 0 ? 1 : -1
            emit(stepCommand(for: slide.action, sign: sign))
            emit(.haptic(.step))
            slide.accumulatedMM -= Float(sign) * step
            slide.stepsEmitted += 1
        }
        if abs(slide.accumulatedMM) >= threshold {
            // The cap was hit: drop the remaining distance instead of paying it out on later frames.
            slide.accumulatedMM = 0
        }
        return true
    }

    /// A non-finite coordinate corrupted the slide: cancel it and wait in `spent` for the fingers to lift.
    private func abandon(_ slide: SlideData, _ frame: Frame) {
        finish(slide, .cancel)
        spend(firstDownTime: slide.firstDownTime, origin: slide.origin, frame)
    }

    private func stepCommand(for action: EdgeAction, sign: Int) -> GestureCommand {
        let fine = config.precision
        switch action {
        case .volume: return .stepVolume(sign, fine: fine)
        case .brightness: return .stepBrightness(sign, fine: fine)
        case .keyboardBacklight: return .stepKeyboardBacklight(sign, fine: fine)
        case .switchApps: return .appSwitchStep(sign)
        case .scrubVideo: return .scrubStep(sign)
        case .media, .off: return sign > 0 ? .mediaNext : .mediaPrevious
        }
    }

    /// Ends a slide: the action's commit or cancel command, then the cursor release. The caller sets the state.
    func finish(_ slide: SlideData, _ outcome: Outcome) {
        switch (slide.action, outcome) {
        case (.switchApps, .commit): emit(.appSwitchCommit)
        case (.switchApps, .cancel): emit(.appSwitchCancel)
        case (.scrubVideo, .commit): emit(.scrubCommit)
        case (.scrubVideo, .cancel): emit(.scrubCancel)
        default: break
        }
        if slide.frozen {
            emit(.freezeCursor(false))
        }
    }

    func emit(_ command: GestureCommand) {
        guard let sink else { return }
        sink.handle(command, device: activeDeviceID)
    }
}

// MARK: - Public API (each call holds the lock)

public extension GestureEngine {
    var stateKind: StateKind {
        lock.withLock { stateKindLocked }
    }

    /// How long a slide waits for a lost finger, from the current configuration (`Thresholds.lostTimeout`).
    var lostTimeout: TimeInterval {
        lock.withLock { config.thresholds.lostTimeout }
    }

    /// Applies a new configuration immediately: an active slide is committed first, and a finger that is
    /// still a candidate is dropped (it waits in `spent` until it lifts).
    func update(config: EngineConfig) {
        lock.withLock { updateLocked(config: config) }
    }

    /// Handles one frame. `frame.timestamp` is in seconds of system uptime
    /// (`ProcessInfo.processInfo.systemUptime`); CGEvent timestamps must be divided by 1e9.
    func process(_ frame: Frame) {
        lock.withLock { processLocked(frame) }
    }

    /// Watchdog: ends a slide whose frames stopped arriving. A `now` earlier than the last frame does nothing.
    /// `now` is in seconds of system uptime (`ProcessInfo.processInfo.systemUptime`); CGEvent timestamps must
    /// be divided by 1e9.
    func tick(now: TimeInterval) {
        lock.withLock { tickLocked(now: now) }
    }

    /// Records a key press; for `typingGate` seconds after it no new gesture starts. An active slide or
    /// middle click is not affected. `time` is in seconds of system uptime
    /// (`ProcessInfo.processInfo.systemUptime`); CGEvent timestamps must be divided by 1e9.
    func noteKeyDown(at time: TimeInterval) {
        lock.withLock { lastKeyDown = time }
    }

    /// Reports whether the Hold-to-Slide key is down. When the key is required and released, an active slide
    /// is committed and any other gesture in progress is dropped without commands.
    func setHoldKeySatisfied(_ satisfied: Bool) {
        lock.withLock { setHoldKeySatisfiedLocked(satisfied) }
    }

    /// Pauses or resumes the engine. Pausing commits an active slide and drops any other gesture without
    /// commands; while paused, every frame is ignored.
    func setPaused(_ paused: Bool) {
        lock.withLock { setPausedLocked(paused) }
    }

    /// Returns to idle. An active slide is cancelled, not committed: an app switch emits `appSwitchCancel`,
    /// a scrub `scrubCancel`, and a frozen cursor is released.
    func reset() {
        lock.withLock { resetLocked() }
    }
}

// MARK: - Locked bodies

private extension GestureEngine {
    var stateKindLocked: StateKind {
        switch state {
        case .idle: .idle
        case .candidate: .candidate
        case .sliding: .sliding
        case .lost: .lost
        case .spent: .spent
        case .threeFinger: .threeFinger
        }
    }

    func updateLocked(config: EngineConfig) {
        switch state {
        case let .sliding(data), let .lost(data, _):
            finish(data, .commit)
            state = .idle
        case let .candidate(data):
            // The candidate was judged under the old configuration; it keeps its landing position.
            var start = TouchBuffer()
            start.append(data.origin)
            enterSpent(firstDownTime: Self.blockedDownTime, start: start)
        case let .threeFinger(_, start, tDown) where !config.middleClickEnabled:
            enterSpent(firstDownTime: tDown, start: start)
        default:
            break
        }
        lastTap = nil
        self.config = config
    }

    /// The gates of spec 5.6 apply in order: palms are dropped from the frame, the typing and hold-key gates
    /// keep new gestures from starting (see `admitsNewGesture(at:)`), and a paused engine ignores the frame
    /// altogether.
    func processLocked(_ rawFrame: Frame) {
        let frame = Self.withoutPalms(rawFrame, maxMajorAxisMM: config.thresholds.palmMajorAxisMM)
        guard !paused else { return }
        if case .idle = state {
            handleIdle(frame)
            return
        }
        guard frame.deviceID == activeDeviceID else { return }
        switch state {
        case .idle: handleIdle(frame)
        case let .candidate(data): handleCandidate(data, frame)
        case let .sliding(data): handleSliding(data, frame)
        case let .lost(data, since): handleLost(data, since: since, frame)
        case let .spent(firstDownTime, start): handleSpent(firstDownTime: firstDownTime, start: start, frame)
        case let .threeFinger(ids, start, tDown): handleThreeFinger(ids: ids, start: start, tDown: tDown, frame)
        }
    }

    func tickLocked(now: TimeInterval) {
        let timeout = config.thresholds.lostTimeout
        switch state {
        case let .sliding(data) where now - data.lastFrameTime >= timeout:
            finish(data, .commit)
            state = .idle
        case let .lost(data, since) where now - since >= timeout:
            finish(data, .commit)
            state = .idle
        default:
            break
        }
    }

    func resetLocked() {
        switch state {
        case let .sliding(data), let .lost(data, _):
            finish(data, .cancel)
        default:
            break
        }
        state = .idle
        lastTap = nil
    }
}
