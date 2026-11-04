import Foundation

/// Taps, double-taps and the three-finger middle click (spec 5.4: the candidate lift branch, `spent` and
/// `threeFinger`). Like the rest of the engine, nothing here allocates on the heap.
extension GestureEngine {
    /// The candidate finger lifted: a quick lift without movement is a tap. Two taps on the same corner, or on
    /// an edge set to media, within the double-tap window fire that corner's action or play/pause.
    func recognizeTap(_ data: CandidateData, liftTime: TimeInterval) {
        let thresholds = config.thresholds
        let quick = max(0, liftTime - data.t0) <= thresholds.tapMaxDuration
        let still = data.maxMoveMM <= thresholds.tapMaxMoveMM
        let previous = lastTap
        lastTap = nil
        guard quick, still else { return }

        var corner: Corner?
        var edge: Edge?
        switch data.zone {
        case let .corner(tapped):
            corner = tapped
        case let .edge(tapped) where config.action(for: tapped) == .media:
            edge = tapped
        default:
            return
        }
        // The window runs from the first tap's lift to the second tap's touch-down.
        guard let previous, previous.corner == corner, previous.edge == edge,
              data.t0 - previous.at <= thresholds.doubleTapWindow
        else {
            lastTap = (corner: corner, edge: edge, at: liftTime)
            return
        }
        if let corner {
            guard let command = Self.command(for: config.action(for: corner)) else { return }
            emit(command)
        } else {
            emit(.mediaPlayPause)
        }
        emit(.haptic(.tap))
    }

    /// The command a corner action fires; `nil` for `.off`.
    static func command(for action: CornerAction) -> GestureCommand? {
        switch action {
        case .off: nil
        case .mute: .mute
        case .screenshot: .screenshot
        case .playPause: .mediaPlayPause
        case .missionControl: .missionControl
        case .appWindows: .appWindows
        case .showDesktop: .showDesktop
        case .spotlight: .spotlight
        case .lockScreen: .lockScreen
        case .screenshotArea: .screenshotArea
        }
    }

    /// Sets the state to `spent`. Fingers in `spent` break a double-tap pair, so the pending tap is dropped.
    func enterSpent(firstDownTime: TimeInterval, start: TouchBuffer) {
        lastTap = nil
        state = .spent(firstDownTime: firstDownTime, start: start)
    }

    /// Enters `spent` from a single tracked finger that will not become a gesture.
    func spend(firstDownTime: TimeInterval, origin: Touch, _ frame: Frame) {
        var start = TouchBuffer()
        start.append(origin)
        handleSpent(firstDownTime: firstDownTime, start: start, frame)
    }

    /// Waits for every finger to lift. Fingers that land are added to `start` as they are on landing; a
    /// landing that brings the count to three, quickly and without movement, arms a middle click. Entering
    /// `spent` or `threeFinger` drops the pending tap of a double-tap pair.
    func handleSpent(firstDownTime: TimeInterval, start: TouchBuffer, _ frame: Frame) {
        lastTap = nil
        let touches = frame.touches
        guard touches.count >= 1 else {
            state = .idle
            return
        }
        var start = start
        let landed = Self.addLandings(touches, to: &start)
        // Only a finger landing can bring the count up to three; dropping back to three from four cannot.
        let armsMiddleClick = landed && touches.count == 3 && admitsNewGesture(at: frame.timestamp)
            && canStartMiddleClick(firstDownTime: firstDownTime, start: start, frame)
        guard armsMiddleClick else {
            state = .spent(firstDownTime: firstDownTime, start: start)
            return
        }
        var landing = TouchBuffer()
        for index in 0 ..< 3 {
            if let origin = start.touch(id: touches[index].id) {
                landing.append(origin)
            }
        }
        state = .threeFinger(ids: (touches[0].id, touches[1].id, touches[2].id), start: landing, tDown: firstDownTime)
    }

    func handleThreeFinger(ids: ThreeFingerIDs, start: TouchBuffer, tDown: TimeInterval, _ frame: Frame) {
        let touches = frame.touches
        var foreign = false
        for index in 0 ..< touches.count {
            let id = touches[index].id
            if id != ids.0, id != ids.1, id != ids.2 {
                foreign = true
            }
        }
        let tooLong = frame.timestamp - tDown > config.thresholds.threeFingerMaxDuration
        let cancelled = touches.count >= 4 || foreign || tooLong
            || anyMovedBeyondTap(touches, from: start, in: frame.geometry)
        if cancelled {
            // Keep the landing positions; this frame never re-arms the click.
            var landings = start
            Self.addLandings(touches, to: &landings)
            if touches.count < 1 {
                state = .idle
            } else {
                enterSpent(firstDownTime: tDown, start: landings)
            }
            return
        }
        // Some of the three are still down: wait for the rest to lift.
        guard touches.count < 1 else { return }
        emit(.middleClick)
        emit(.haptic(.tap))
        state = .idle
    }

    /// Appends the touches whose ids are not in `start` yet, at their current (landing) positions.
    /// Returns whether any was added.
    @discardableResult
    static func addLandings(_ touches: TouchBuffer, to start: inout TouchBuffer) -> Bool {
        var landed = false
        for index in 0 ..< touches.count where !start.contains(id: touches[index].id) {
            start.append(touches[index])
            landed = true
        }
        return landed
    }

    /// The larger of the horizontal and vertical distances between two touches, in mm.
    static func axisMoveMM(from origin: Touch, to touch: Touch, in geometry: DeviceGeometry) -> Float {
        let dx = abs(touch.x - origin.x) * geometry.widthMM
        let dy = abs(touch.y - origin.y) * geometry.heightMM
        return max(dx, dy)
    }

    private func canStartMiddleClick(firstDownTime: TimeInterval, start: TouchBuffer, _ frame: Frame) -> Bool {
        guard config.middleClickEnabled,
              frame.timestamp - firstDownTime <= config.thresholds.threeFingerSettle
        else { return false }
        return !anyMovedBeyondTap(frame.touches, from: start, in: frame.geometry)
    }

    /// Whether any of `touches` is more than `tapMaxMoveMM` (on either axis) from its position in `start`.
    /// A touch missing from `start` counts as moved.
    private func anyMovedBeyondTap(
        _ touches: TouchBuffer,
        from start: TouchBuffer,
        in geometry: DeviceGeometry
    ) -> Bool {
        let limit = config.thresholds.tapMaxMoveMM
        for index in 0 ..< touches.count {
            let touch = touches[index]
            guard let origin = start.touch(id: touch.id) else { return true }
            if Self.axisMoveMM(from: origin, to: touch, in: geometry) > limit {
                return true
            }
        }
        return false
    }
}
