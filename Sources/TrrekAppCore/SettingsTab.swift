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
        case .general: String(localized: "General", bundle: .main)
        case .edges: String(localized: "Edges", bundle: .main)
        case .corners: String(localized: "Corners & Taps", bundle: .main)
        case .advanced: String(localized: "Advanced", bundle: .main)
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
