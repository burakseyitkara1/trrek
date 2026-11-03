public enum Geometry {
    /// Classifies a touch (normalized, origin bottom-left) into an edge strip, a corner or nothing.
    public static func zone(of touch: Touch, in geometry: DeviceGeometry, config: EngineConfig) -> Zone {
        guard geometry.isValid else { return .none }
        let width = config.thresholds.edgeWidthMM
        let padWidth = geometry.widthMM
        let padHeight = geometry.heightMM

        var vertical: Edge?
        if touch.x * padWidth < width, config.left != .off {
            vertical = .left
        } else if (1 - touch.x) * padWidth < width, config.right != .off {
            vertical = .right
        }
        var horizontal: Edge?
        if touch.y * padHeight < width, config.bottom != .off {
            horizontal = .bottom
        } else if (1 - touch.y) * padHeight < width, config.top != .off {
            horizontal = .top
        }

        if config.bottomQuarterOnly, vertical != nil, touch.y >= 0.25 {
            return .none
        }
        switch (vertical, horizontal) {
        case let (.some(vert), .some(hz)): return .corner(corner(vertical: vert, horizontal: hz))
        case let (.some(vert), nil): return .edge(vert)
        case let (nil, .some(hz)): return .edge(hz)
        case (nil, nil): return .none
        }
    }

    /// Movement in mm split into the component along the edge and the one perpendicular to it.
    public static func deltaMM(
        edge: Edge,
        from: Touch,
        to: Touch,
        in geometry: DeviceGeometry
    ) -> (along: Float, perpendicular: Float) {
        let dx = (to.x - from.x) * geometry.widthMM
        let dy = (to.y - from.y) * geometry.heightMM
        switch edge {
        case .left, .right: return (dy, dx)
        case .top, .bottom: return (dx, dy)
        }
    }

    public static func stepMM(for action: EdgeAction, thresholds: Thresholds) -> Float {
        switch action {
        case .volume, .brightness, .keyboardBacklight: thresholds.stepMM
        case .switchApps: thresholds.appSwitchStepMM
        case .scrubVideo: thresholds.scrubStepMM
        case .media: thresholds.mediaSkipStepMM
        case .off: .infinity
        }
    }

    public static func edges(of corner: Corner) -> (vertical: Edge, horizontal: Edge) {
        switch corner {
        case .topLeft: (.left, .top)
        case .topRight: (.right, .top)
        case .bottomLeft: (.left, .bottom)
        case .bottomRight: (.right, .bottom)
        }
    }

    private static func corner(vertical: Edge, horizontal: Edge) -> Corner {
        switch (vertical, horizontal) {
        case (.left, .top): .topLeft
        case (.right, .top): .topRight
        case (.left, _): .bottomLeft
        default: .bottomRight
        }
    }
}
