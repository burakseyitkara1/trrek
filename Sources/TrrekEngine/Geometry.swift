public enum Geometry {
    /// With `bottomQuarterOnly`, vertical-edge slides start only below this normalized height.
    static let bottomQuarter: Float = 0.25

    /// Classifies a touch (normalized, origin bottom-left) into an edge strip, a corner or nothing.
    /// Strips are found by geometry alone, so where two strips meet is always a corner, also when one or both of
    /// its edges are off: a corner's double tap does not depend on its edges, and a slide from it toward an edge
    /// that is off never starts (the engine spends the finger). An edge that is off only stops being a plain
    /// edge zone. With `bottomQuarterOnly`, a vertical strip at or above the bottom quarter is not an edge zone but
    /// still forms corners with a horizontal strip; the engine then lets such a corner slide only horizontally.
    public static func zone(of touch: Touch, in geometry: DeviceGeometry, config: EngineConfig) -> Zone {
        guard geometry.isValid else { return .none }
        let width = config.thresholds.edgeWidthMM
        let padWidth = geometry.widthMM
        let padHeight = geometry.heightMM

        var vertical: Edge?
        if touch.x * padWidth < width {
            vertical = .left
        } else if (1 - touch.x) * padWidth < width {
            vertical = .right
        }
        var horizontal: Edge?
        if touch.y * padHeight < width {
            horizontal = .bottom
        } else if (1 - touch.y) * padHeight < width {
            horizontal = .top
        }

        let verticalEdgeAllowed = !(config.bottomQuarterOnly && touch.y >= bottomQuarter)
        switch (vertical, horizontal) {
        case let (.some(vert), .some(hz)):
            return .corner(corner(vertical: vert, horizontal: hz))
        case let (.some(vert), nil):
            return verticalEdgeAllowed && config.action(for: vert) != .off ? .edge(vert) : .none
        case let (nil, .some(hz)):
            return config.action(for: hz) != .off ? .edge(hz) : .none
        case (nil, nil):
            return .none
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
        case .switchTabs: thresholds.tabSwitchStepMM
        case .switchDesktops: thresholds.desktopSwitchStepMM
        case .zoom: thresholds.zoomStepMM
        case .undoRedo: thresholds.undoRedoStepMM
        case .off: .infinity
        }
    }

    /// The command for one step of `action`: `sign` +1 is forward (rightward on a horizontal edge, upward on a
    /// vertical one), -1 back. `fine` is the Precision Control flag of the level steps.
    static func stepCommand(for action: EdgeAction, sign: Int, fine: Bool) -> GestureCommand {
        switch action {
        case .volume: .stepVolume(sign, fine: fine)
        case .brightness: .stepBrightness(sign, fine: fine)
        case .keyboardBacklight: .stepKeyboardBacklight(sign, fine: fine)
        case .switchApps: .appSwitchStep(sign)
        case .switchTabs: .tabSwitchStep(sign)
        case .switchDesktops: .desktopSwitchStep(sign)
        case .scrubVideo: .scrubStep(sign)
        case .media, .off: sign > 0 ? .mediaNext : .mediaPrevious
        case .zoom: .zoomStep(sign)
        case .undoRedo: .undoRedoStep(sign)
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

    /// The edge a slide binds to. A corner picks its neighbouring edge by the dominant movement axis.
    /// Returns `nil` for `.none`, which never becomes a candidate; the caller then gives up on the finger.
    static func slideEdge(for zone: Zone, from origin: Touch, to touch: Touch, in geometry: DeviceGeometry) -> Edge? {
        switch zone {
        case let .edge(edge):
            return edge
        case let .corner(corner):
            let edges = edges(of: corner)
            let dx = abs(touch.x - origin.x) * geometry.widthMM
            let dy = abs(touch.y - origin.y) * geometry.heightMM
            return dx >= dy ? edges.horizontal : edges.vertical
        case .none:
            assertionFailure("a candidate never has zone .none")
            return nil
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
