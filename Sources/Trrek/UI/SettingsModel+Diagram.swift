import TrrekAppCore
import TrrekEngine

/// An edge or corner of the trackpad diagram that opens a menu of its actions.
enum DiagramControl: Hashable {
    case edge(Edge)
    case corner(Corner)
}

/// Why an edge or corner on the diagram does not run the action chosen for it; shown as a small badge with this
/// text as its tooltip.
enum DiagramNote: Equatable {
    /// The action posts events, which need Accessibility access; it is off until the access is granted.
    case needsAccessibility
    /// The keyboard backlight was chosen, but this Mac has no bridge for it, so the edge runs media control.
    case backlightUnavailable

    var text: String {
        switch self {
        case .needsAccessibility:
            return String(localized: "Needs Accessibility access", bundle: .main)
        case .backlightUnavailable:
            let name = SettingsLabels.title(for: EdgeAction.keyboardBacklight)
            let reason = String(localized: "Not available on this Mac", bundle: .main)
            return String(localized: "\(name) — \(reason)", bundle: .main)
        }
    }
}

/// An item of an edge's menu on the diagram.
struct EdgeMenuOption: Hashable, Identifiable {
    /// The action it sets; `nil` for Same as All Apps, which an app's edge offers first.
    let action: EdgeAction?
    /// The action's name with its note ("Scrub Video — Uses ← and → in the front app"), or "Same as All Apps (…)".
    let title: String
    let symbol: String?
    /// The keyboard backlight is listed but cannot be chosen while its bridge is missing.
    let isEnabled: Bool

    var id: EdgeAction? {
        action
    }
}

/// What the diagram shows on one edge in the Edges tab.
struct DiagramEdgeItem: Equatable {
    let edge: Edge
    /// The action chosen for the shown scope, as it runs on this Mac (the keyboard backlight as media control while
    /// its bridge is missing).
    let action: EdgeAction
    /// Whether the shown app uses the All Apps action for this edge.
    let isInherited: Bool
    let note: DiagramNote?

    /// "Brightness", or "Same as All Apps (Brightness)" for an app's edge that uses the All Apps action.
    let valueTitle: String
}

/// What the diagram shows on one corner in the Corners & Taps tab.
struct DiagramCornerItem: Equatable {
    let corner: Corner
    let action: CornerAction
    let note: DiagramNote?
}

/// The edge and corner menus of the trackpad diagram, for the shown scope.
extension SettingsModel {
    // MARK: - Edges

    /// The actions in the order the engine lists them, Off last; an app's edge starts with Same as All Apps.
    func edgeMenuOptions(for edge: Edge) -> [EdgeMenuOption] {
        let available = backlightAvailable
        let actions = EdgeChoices.all.map { action in
            let name = SettingsLabels.title(for: action)
            let caption = EdgeChoices.caption(for: action, backlightAvailable: available)
            return EdgeMenuOption(
                action: action,
                title: caption.map { String(localized: "\(name) — \($0)", bundle: .main) } ?? name,
                symbol: SettingsLabels.symbol(for: action),
                isEnabled: EdgeChoices.isSelectable(action, backlightAvailable: available)
            )
        }
        guard edgeScope != nil else { return actions }
        let inherited = EdgeMenuOption(action: nil, title: inheritedEdgeTitle(for: edge), symbol: nil, isEnabled: true)
        return [inherited] + actions
    }

    /// The checked item of an edge's menu: the All Apps action, or the shown app's own one (`nil` for Same as All
    /// Apps). The keyboard backlight shows as media control while its bridge is missing.
    func edgeMenuSelection(for edge: Edge) -> EdgeAction? {
        let chosen = edgeScope == nil ? settings[edge: edge] : edgeOverride(edge)
        return chosen.map { EdgeChoices.displayed($0, backlightAvailable: backlightAvailable) }
    }

    /// Sets `edge` in the shown scope; `nil` makes an app's edge the same as All Apps (and is ignored for All Apps).
    func chooseEdgeAction(_ action: EdgeAction?, for edge: Edge) {
        if edgeScope == nil {
            guard let action else { return }
            settings[edge: edge] = action
        } else {
            setEdgeOverride(edge, to: action)
        }
    }

    func diagramEdge(_ edge: Edge) -> DiagramEdgeItem {
        let chosen = settings.edgeActions(for: edgeScope)[edge]
        let shown = shownEdgeAction(edge)
        let note: DiagramNote? = if ConfigMapper.gated(shown, accessibilityTrusted: accessibilityGranted) != shown {
            .needsAccessibility
        } else if chosen != shown {
            .backlightUnavailable
        } else {
            nil
        }
        let isInherited = edgeScope != nil && edgeOverride(edge) == nil
        return DiagramEdgeItem(
            edge: edge,
            action: shown,
            isInherited: isInherited,
            note: note,
            valueTitle: isInherited ? inheritedEdgeTitle(for: edge) : SettingsLabels.title(for: shown)
        )
    }

    // MARK: - Corners

    /// Every corner action in the order the engine lists them, Off first.
    var cornerMenuOptions: [CornerAction] {
        CornerAction.allCases
    }

    func chooseCornerAction(_ action: CornerAction, for corner: Corner) {
        settings[corner: corner] = action
    }

    func diagramCorner(_ corner: Corner) -> DiagramCornerItem {
        let action = settings[corner: corner]
        let gated = ConfigMapper.gated(action, accessibilityTrusted: accessibilityGranted) != action
        return DiagramCornerItem(corner: corner, action: action, note: gated ? .needsAccessibility : nil)
    }

    /// Whether any edge of the shown scope waits for Accessibility access.
    var diagramEdgesNeedAccessibility: Bool {
        Edge.allCases.contains { diagramEdge($0).note == .needsAccessibility }
    }

    /// Whether any corner waits for Accessibility access.
    var diagramCornersNeedAccessibility: Bool {
        Corner.allCases.contains { diagramCorner($0).note == .needsAccessibility }
    }
}
