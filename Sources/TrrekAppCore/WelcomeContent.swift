import TrrekEngine

/// One of the welcome window's edge cards.
public struct WelcomeCard: Equatable, Sendable {
    public var edge: Edge
    public var action: EdgeAction
    /// "Right edge — Volume"; the action is named as the diagram and the settings window name it.
    public var title: String
    /// One short line on how to use the edge.
    public var detail: String

    public init(edge: Edge, action: EdgeAction, title: String, detail: String) {
        self.edge = edge
        self.action = action
        self.title = title
        self.detail = detail
    }
}

/// What the welcome window says about each edge.
public enum WelcomeContent {
    /// The right, left, top and bottom edge cards for `settings`: Swap Sides moves volume to the left, and the
    /// bottom edge shows media control while the keyboard backlight bridge is unavailable.
    public static func cards(for settings: Settings, backlightAvailable: Bool) -> [WelcomeCard] {
        let edges = DiagramEdges(settings: settings, backlightAvailable: backlightAvailable)
        return [
            card(.right, edges.right),
            card(.left, edges.left),
            card(.top, edges.top),
            card(.bottom, edges.bottom)
        ]
    }

    private static func card(_ edge: Edge, _ action: EdgeAction) -> WelcomeCard {
        WelcomeCard(
            edge: edge,
            action: action,
            title: "\(name(of: edge)) edge — \(SettingsLabels.title(for: action))",
            detail: detail(for: action)
        )
    }

    private static func name(of edge: Edge) -> String {
        switch edge {
        case .left: "Left"
        case .right: "Right"
        case .top: "Top"
        case .bottom: "Bottom"
        }
    }

    private static func detail(for action: EdgeAction) -> String {
        switch action {
        case .volume: "Slide to turn the sound up or down."
        case .brightness: "Slide to brighten or dim the display."
        case .switchApps: "Slide to pick an app, lift to switch."
        case .scrubVideo: "Slide to move through a video."
        case .keyboardBacklight: "Slide to brighten or dim the keys."
        case .media: "Slide to skip, double-tap to play."
        case .off: "Does nothing."
        }
    }
}
