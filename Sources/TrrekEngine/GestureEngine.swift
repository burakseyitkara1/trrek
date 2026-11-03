import Foundation

public enum StateKind: Sendable, Equatable {
    case idle, candidate, sliding, lost, spent, threeFinger
}

/// Turns multitouch frames into gesture commands.
///
/// Not thread-safe by design: the caller must serialize every call (`process`, `tick`, `update`, the host
/// signals and `reset`), for example by calling them all from one queue. There are no locks inside, hence
/// `@unchecked Sendable`. The engine never allocates on the heap while handling a frame.
///
/// The sink is held weakly so that the engine never keeps its owner alive; commands emitted after the sink
/// has gone away are dropped.
public final class GestureEngine: @unchecked Sendable {
    private enum Outcome {
        case commit, cancel
    }

    /// Absorbs float rounding when converting normalized positions to mm, so an exact multiple of the
    /// step distance always yields that many steps.
    private static let stepToleranceMM: Float = 0.001

    private weak var sink: CommandSink?
    private var config: EngineConfig
    private var state: EngineState = .idle
    private var activeDeviceID: UInt64 = 0

    // Host signals; the gates that read them are applied by `admitsNewGesture(at:)`.
    private var lastKeyDown: TimeInterval = -.infinity
    private var holdKeySatisfied = false
    private var paused = false

    public init(config: EngineConfig, sink: CommandSink) {
        self.config = config
        self.sink = sink
    }

    public var stateKind: StateKind {
        switch state {
        case .idle: .idle
        case .candidate: .candidate
        case .sliding: .sliding
        case .lost: .lost
        case .spent: .spent
        case .threeFinger: .threeFinger
        }
    }

    /// Applies a new configuration immediately; an active slide is committed first.
    public func update(config: EngineConfig) {
        switch state {
        case let .sliding(data), let .lost(data, _):
            finish(data, .commit)
            state = .idle
        default:
            break
        }
        self.config = config
    }

    public func process(_ frame: Frame) {
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
        case .spent: handleSpent(frame)
        case .threeFinger: handleSpent(frame)
        }
    }

    /// Watchdog: ends a slide whose frames stopped arriving. A `now` earlier than the last frame does nothing.
    public func tick(now: TimeInterval) {
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

    public func noteKeyDown(at time: TimeInterval) {
        lastKeyDown = time
    }

    public func setHoldKeySatisfied(_ satisfied: Bool) {
        holdKeySatisfied = satisfied
    }

    public func setPaused(_ paused: Bool) {
        self.paused = paused
    }

    /// Returns to idle. An active slide only releases the cursor; its action is not committed.
    public func reset() {
        switch state {
        case let .sliding(data), let .lost(data, _):
            if data.frozen {
                emit(.freezeCursor(false))
            }
        default:
            break
        }
        state = .idle
    }

    // MARK: - States

    private func handleIdle(_ frame: Frame) {
        let touches = frame.touches
        guard touches.count >= 1, admitsNewGesture(at: frame.timestamp) else { return }
        activeDeviceID = frame.deviceID
        guard touches.count == 1 else {
            state = .spent(firstDownTime: frame.timestamp)
            return
        }
        let touch = touches[0]
        let zone = Geometry.zone(of: touch, in: frame.geometry, config: config)
        if zone == .none {
            state = .spent(firstDownTime: frame.timestamp)
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
        if touches.count >= 2 {
            state = .spent(firstDownTime: data.t0)
            return
        }
        guard let touch = touches.touch(id: data.touchID) else {
            // Lift (taps are recognized here by the tap rules); a different finger starts over from idle.
            state = .idle
            handleIdle(frame)
            return
        }
        let origin = Touch(id: data.touchID, x: data.x0, y: data.y0, majorAxisMM: touch.majorAxisMM)
        let edge = slideEdge(for: data.zone, from: origin, to: touch, in: frame.geometry)
        let delta = Geometry.deltaMM(edge: edge, from: origin, to: touch, in: frame.geometry)
        let thresholds = config.thresholds
        if abs(delta.along) >= thresholds.slideStartMM {
            let action = config.action(for: edge)
            guard action != .off else {
                state = .spent(firstDownTime: data.t0)
                return
            }
            startSlide(edge: edge, action: action, touch: touch, alongMM: delta.along, time: frame.timestamp)
        } else if abs(delta.perpendicular) >= thresholds.abortPerpendicularMM {
            state = .spent(firstDownTime: data.t0)
        }
    }

    private func handleSliding(_ data: SlideData, _ frame: Frame) {
        if frame.touches.count >= 2 {
            finish(data, .cancel)
            state = .spent(firstDownTime: frame.timestamp)
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
        emitSteps(&slide)
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

    private func handleSpent(_ frame: Frame) {
        if frame.touches.count < 1 {
            state = .idle
        }
    }

    // MARK: - Slides

    private func startSlide(edge: Edge, action: EdgeAction, touch: Touch, alongMM: Float, time: TimeInterval) {
        let frozen = config.freezeCursor
        if frozen {
            emit(.freezeCursor(true))
        }
        emit(.haptic(.start))
        var slide = SlideData(
            edge: edge,
            action: action,
            touchID: touch.id,
            previous: touch,
            accumulatedMM: alongMM,
            stepsEmitted: 0,
            lastFrameTime: time,
            frozen: frozen
        )
        emitSteps(&slide)
        state = .sliding(slide)
    }

    private func emitSteps(_ slide: inout SlideData) {
        let step = Geometry.stepMM(for: slide.action, thresholds: config.thresholds)
        guard step.isFinite, step > 0 else { return }
        let threshold = step - Self.stepToleranceMM
        while abs(slide.accumulatedMM) >= threshold {
            let sign = slide.accumulatedMM > 0 ? 1 : -1
            emit(stepCommand(for: slide.action, sign: sign))
            emit(.haptic(.step))
            slide.accumulatedMM -= Float(sign) * step
            slide.stepsEmitted += 1
        }
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
    private func finish(_ slide: SlideData, _ outcome: Outcome) {
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

    /// The edge a slide binds to. A corner picks its neighbouring edge by the dominant movement axis.
    private func slideEdge(for zone: Zone, from origin: Touch, to touch: Touch, in geometry: DeviceGeometry) -> Edge {
        switch zone {
        case let .edge(edge):
            return edge
        case let .corner(corner):
            let edges = Geometry.edges(of: corner)
            let dx = abs(touch.x - origin.x) * geometry.widthMM
            let dy = abs(touch.y - origin.y) * geometry.heightMM
            return dx >= dy ? edges.horizontal : edges.vertical
        case .none:
            return .right
        }
    }

    // MARK: - Gates

    /// Whether a new gesture may begin. The typing, hold-key and pause gates plug in here; none apply yet.
    private func admitsNewGesture(at _: TimeInterval) -> Bool {
        true
    }

    private func emit(_ command: GestureCommand) {
        guard let sink else { return }
        sink.handle(command, device: activeDeviceID)
    }
}
