import SwiftUI
import TrrekAppCore
import TrrekEngine

/// The edge layout: whose edges are shown (All Apps or one app), the diagram, the action of each edge and the strip
/// geometry.
struct EdgesTab: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section {
                scopePicker
                if let bundleID = model.edgeScope {
                    scopeFooter(name: model.appInfo(for: bundleID).name)
                }
            }
            Section {
                edgePicker("Left Edge", edge: .left)
                edgePicker("Right Edge", edge: .right)
                edgePicker("Top Edge", edge: .top)
                edgePicker("Bottom Edge", edge: .bottom)
            } header: {
                TrackpadDiagram(
                    settings: model.settings,
                    backlightAvailable: model.backlightAvailable,
                    accessibilityGranted: model.accessibilityGranted,
                    interactive: true,
                    onChange: { model.settings = $0 },
                    height: TrackpadDiagram.compactHeight,
                    bundleID: model.edgeScope
                )
                .frame(maxWidth: .infinity)
                .padding(.bottom, -4)
            }
            Section {
                Picker("Edge Width", selection: $model.settings.edgeWidth) {
                    ForEach(EdgeWidth.allCases, id: \.self) { width in
                        Text(SettingsLabels.title(for: width)).tag(width)
                    }
                }
                .pickerStyle(.segmented)
                Toggle(isOn: $model.settings.bottomQuarterOnly) {
                    Text("Bottom Quarter Only")
                    Text("The side edges respond only in their lower quarter.")
                }
                externalBrightnessToggle
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
        return Picker("Edges For", selection: selection) {
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
        }
        .id(model.edgeScopePickerID)
    }

    private func scopeFooter(name: String) -> some View {
        HStack(spacing: 12) {
            Text("These edges apply while \(name) is in front.")
                .font(.footnote)
                .foregroundStyle(.secondary)
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

    /// A picker for one edge of the shown scope. Options that cannot be used on this Mac are listed but disabled, with
    /// the reason; the keyboard backlight shows as media control while its bridge is missing. For an app, the first
    /// option keeps the All Apps action. Without Accessibility, a caption under the title says the action the edge
    /// runs cannot run yet.
    @ViewBuilder
    private func edgePicker(_ title: LocalizedStringKey, edge: TrrekEngine.Edge) -> some View {
        let available = model.backlightAvailable
        let gated = ConfigMapper.gated(model.shownEdgeAction(edge), accessibilityTrusted: model.accessibilityGranted)
            != model.shownEdgeAction(edge)
        let label = Group {
            Text(title)
            if gated {
                Text("Needs Accessibility access")
            }
        }
        if model.edgeScope == nil {
            let selection = Binding(
                get: { EdgeChoices.displayed(model.settings[edge: edge], backlightAvailable: available) },
                set: { model.settings[edge: edge] = $0 }
            )
            Picker(selection: selection) {
                options { $0 }
            } label: {
                label
            }
        } else {
            let selection = Binding(
                get: { model.edgeOverride(edge).map { EdgeChoices.displayed($0, backlightAvailable: available) } },
                set: { model.setEdgeOverride(edge, to: $0) }
            )
            Picker(selection: selection) {
                Text(model.inheritedEdgeTitle(for: edge)).tag(EdgeAction?.none)
                Divider()
                options { Optional($0) }
            } label: {
                label
            }
        }
    }

    /// Every edge action, tagged with `tag(action)`.
    private func options(_ tag: @escaping (EdgeAction) -> some Hashable) -> some View {
        let available = model.backlightAvailable
        return ForEach(EdgeChoices.all, id: \.self) { choice in
            let name = SettingsLabels.title(for: choice)
            if let caption = EdgeChoices.caption(for: choice, backlightAvailable: available) {
                Text("\(name) — \(caption)").tag(tag(choice))
                    .disabled(!EdgeChoices.isSelectable(choice, backlightAvailable: available))
            } else {
                Text(name).tag(tag(choice))
            }
        }
    }
}
