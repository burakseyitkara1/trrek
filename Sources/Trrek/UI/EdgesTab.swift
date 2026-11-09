import SwiftUI
import TrrekAppCore
import TrrekEngine

/// The edge layout: whose edges are shown (All Apps or one app), the diagram, whose edge labels are menus of the
/// edge actions, and the strip geometry.
struct EdgesTab: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section {
                scopePicker
                if let bundleID = model.edgeScope {
                    removeButton(name: model.appInfo(for: bundleID).name)
                }
            }
            Section {
                Picker(selection: $model.settings.edgeWidth) {
                    ForEach(EdgeWidth.allCases, id: \.self) { width in
                        Text(SettingsLabels.title(for: width)).tag(width)
                    }
                } label: {
                    Text("Edge Width")
                    Text("How far from the edge a touch starts a slide.")
                }
                .pickerStyle(.segmented)
                Toggle(isOn: $model.settings.bottomQuarterOnly) {
                    Text("Bottom Quarter Only")
                    Text("The side edges respond only in their lower quarter.")
                }
                externalBrightnessToggle
            } header: {
                DiagramHeader(
                    diagram: TrackpadDiagram(
                        settings: model.settings,
                        backlightAvailable: model.backlightAvailable,
                        accessibilityGranted: model.accessibilityGranted,
                        editing: .edges(model),
                        maxHeight: TrackpadDiagram.compactHeight,
                        bundleID: model.edgeScope,
                        trackpad: model.diagramTrackpad
                    ),
                    caption: String(localized: "Click an edge in the diagram to change its action.", bundle: .main),
                    needsAccessibility: model.diagramEdgesNeedAccessibility
                )
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Scope

    /// All Apps, each app with edges of its own (icon and name), then Add App…, which opens the app chooser and
    /// shows the added app.
    private var scopePicker: some View {
        let selection = Binding(
            get: { model.edgeScopeChoice },
            set: { (choice: EdgeScopeChoice) in
                switch choice {
                case .allApps: model.edgeScope = nil
                case let .app(bundleID): model.edgeScope = bundleID
                case .add:
                    // The menu already shows Add App… as chosen; rebuilding the picker shows the scope again.
                    model.edgeScopePickerID += 1
                    chooseApp()
                }
            }
        )
        return Picker(selection: selection) {
            Text("All Apps").tag(EdgeScopeChoice.allApps)
            if !model.settings.appEdgeProfiles.isEmpty {
                Divider()
            }
            ForEach(model.settings.appEdgeProfiles, id: \.bundleID) { profile in
                let app = model.appInfo(for: profile.bundleID)
                Label {
                    Text(app.name)
                } icon: {
                    Image(nsImage: app.menuIcon)
                }
                .tag(EdgeScopeChoice.app(profile.bundleID))
            }
            if model.canAddEdgeProfile {
                Divider()
                Text("Add App…").tag(EdgeScopeChoice.add)
            }
        } label: {
            Text("Edges For")
            // The caption says when the shown app's edges apply.
            if let bundleID = model.edgeScope {
                Text("These edges apply while \(model.appInfo(for: bundleID).name) is in front.")
            }
        }
        .id(model.edgeScopePickerID)
    }

    /// On its own row, so a long app name never squeezes it or the caption above.
    private func removeButton(name: String) -> some View {
        HStack {
            Spacer()
            Button("Remove \(name)") {
                model.removeEdgeProfile()
            }
        }
    }

    private func chooseApp() {
        let model = model
        AppChooser.choose(
            title: String(localized: "Choose an App", bundle: .main),
            allowsMultipleSelection: false,
            model: model
        ) { urls in
            guard let url = urls.first else { return }
            model.addEdgeProfile(at: url)
        }
    }

    // MARK: - Edges

    /// Disabled and shown off, with the reason, while the DDC/CI bridge is missing.
    private var externalBrightnessToggle: some View {
        let available = model.externalBrightnessAvailable
        let isOn = Binding(
            get: { available && model.settings.externalMonitorBrightness },
            set: { model.settings.externalMonitorBrightness = $0 }
        )
        return Toggle(isOn: isOn) {
            Text("External Monitor Brightness")
            Text(SettingsLabels.externalBrightnessCaption(available: available))
        }
        .disabled(!available)
    }
}
