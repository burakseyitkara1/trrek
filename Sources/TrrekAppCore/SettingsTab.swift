/// The tabs of the settings window, in order.
public enum SettingsTab: String, CaseIterable, Sendable {
    case general, edges, corners, advanced

    /// Parses the value given after `--settings`, ignoring case; `nil` for no or an unknown tab.
    public init?(argument: String?) {
        guard let argument, let tab = SettingsTab(rawValue: argument.lowercased()) else { return nil }
        self = tab
    }

    public var title: String {
        switch self {
        case .general: "General"
        case .edges: "Edges"
        case .corners: "Corners & Taps"
        case .advanced: "Advanced"
        }
    }

    public var symbol: String {
        switch self {
        case .general: "gearshape"
        case .edges: "rectangle.dashed"
        case .corners: "hand.tap"
        case .advanced: "slider.horizontal.3"
        }
    }
}
