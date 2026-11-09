import AppKit
import TrrekAppCore
import TrrekEngine

/// An item of the Edges For picker.
enum EdgeScopeChoice: Hashable {
    case allApps
    case app(String)
    /// Add App…: opens the app chooser; never stays selected.
    case add
}

/// The Edges tab's scope: All Apps, or one app with edges of its own.
extension SettingsModel {
    /// The picker item for the current scope.
    var edgeScopeChoice: EdgeScopeChoice {
        edgeScope.map(EdgeScopeChoice.app) ?? .allApps
    }

    /// Whether another app can get edges of its own.
    var canAddEdgeProfile: Bool {
        settings.appEdgeProfiles.count < AppSettings.maximumEdgeProfiles
    }

    /// Adds the app at `url` (from the app chooser) and shows its edges; anything without a bundle ID is skipped.
    func addEdgeProfile(at url: URL) {
        guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        addEdgeProfile(bundleID: bundleID)
    }

    /// Gives the app with `bundleID` edges of its own, all the same as All Apps, and shows them. An app that has
    /// them already is only shown. trrek itself is skipped (its windows never decide the edges), and nothing is
    /// added past `maximumEdgeProfiles`.
    func addEdgeProfile(bundleID: String) {
        guard !bundleID.isEmpty, bundleID != AppIdentity.bundleID else { return }
        if settings.edgeProfile(for: bundleID) == nil {
            guard canAddEdgeProfile else { return }
            settings.appEdgeProfiles.append(AppEdgeProfile(bundleID: bundleID))
        }
        edgeScope = bundleID
    }

    /// Removes the shown app's edges and goes back to All Apps.
    func removeEdgeProfile() {
        guard let edgeScope else { return }
        settings.appEdgeProfiles.removeAll { $0.bundleID == edgeScope }
        self.edgeScope = nil
    }

    /// The shown app's own action for `edge`, `nil` when it uses the All Apps one (or All Apps is shown).
    func edgeOverride(_ edge: Edge) -> EdgeAction? {
        settings.edgeProfile(for: edgeScope)?[edge: edge]
    }

    /// Sets the shown app's own action for `edge`; `nil` makes it the same as All Apps.
    func setEdgeOverride(_ edge: Edge, to action: EdgeAction?) {
        guard let edgeScope else { return }
        settings.updateEdgeProfile(for: edgeScope) { $0[edge: edge] = action }
    }

    /// The action `edge` runs in the shown scope, as the diagram shows it (the keyboard backlight as media control
    /// while its bridge is unavailable).
    func shownEdgeAction(_ edge: Edge) -> EdgeAction {
        EdgeChoices.displayed(settings.edgeActions(for: edgeScope)[edge], backlightAvailable: backlightAvailable)
    }

    /// The first item of an app's edge menu on the diagram: "Same as All Apps (<the All Apps action>)".
    func inheritedEdgeTitle(for edge: Edge) -> String {
        let action = EdgeChoices.displayed(settings[edge: edge], backlightAvailable: backlightAvailable)
        let name = SettingsLabels.title(for: action)
        return String(localized: "Same as All Apps (\(name))", bundle: .main)
    }
}
