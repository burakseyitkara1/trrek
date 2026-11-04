import TrrekEngine

/// One of the welcome window's edge cards.
public struct WelcomeCard: Equatable, Sendable {
    public var edge: Edge
    public var action: EdgeAction
    /// "Right edge — Volume"; the action is named as the diagram and the settings window name it.
    public var title: String
    /// One short line on how to use the edge.
    public var detail: String
    /// The edge is set to `action` but does nothing until Accessibility is granted.
    public var needsAccessibility: Bool

    public init(edge: Edge, action: EdgeAction, title: String, detail: String, needsAccessibility: Bool = false) {
        self.edge = edge
        self.action = action
        self.title = title
        self.detail = detail
        self.needsAccessibility = needsAccessibility
    }
}

/// What the welcome window says about each edge.
public enum WelcomeContent {
    /// The right, left, top and bottom edge cards for `settings`: Swap Sides moves volume to the left, and the
    /// bottom edge shows media control while the keyboard backlight bridge is unavailable. Without Accessibility,
    /// a card still names the configured action but says it needs the permission (the diagram shows it off).
    public static func cards(
        for settings: Settings,
        backlightAvailable: Bool,
        accessibilityTrusted: Bool
    ) -> [WelcomeCard] {
        let edges = DiagramEdges(settings: settings, backlightAvailable: backlightAvailable, accessibilityTrusted: true)
        return [
            card(.right, edges.right, accessibilityTrusted),
            card(.left, edges.left, accessibilityTrusted),
            card(.top, edges.top, accessibilityTrusted),
            card(.bottom, edges.bottom, accessibilityTrusted)
        ]
    }

    private static func card(_ edge: Edge, _ action: EdgeAction, _ trusted: Bool) -> WelcomeCard {
        let gated = ConfigMapper.gated(action, accessibilityTrusted: trusted) != action
        return WelcomeCard(
            edge: edge,
            action: action,
            title: "\(name(of: edge)) edge — \(SettingsLabels.title(for: action))",
            detail: gated ? "Needs Accessibility access." : detail(for: action),
            needsAccessibility: gated
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
