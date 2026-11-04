import SwiftUI
import TrrekAppCore
import TrrekEngine

/// The edge layout: the diagram, the action of each edge and the strip geometry.
struct EdgesTab: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section {
                edgePicker("Left Edge", action: \.leftEdge)
                edgePicker("Right Edge", action: \.rightEdge)
                edgePicker("Top Edge", action: \.topEdge)
                edgePicker("Bottom Edge", action: \.bottomEdge)
            } header: {
                TrackpadDiagram(
                    settings: model.settings,
                    backlightAvailable: model.backlightAvailable,
                    accessibilityGranted: model.accessibilityGranted,
                    interactive: true,
                    onChange: { model.settings = $0 },
                    height: TrackpadDiagram.compactHeight
                )
                .frame(maxWidth: .infinity)
                // Pulled up into the space under the tab bar, so the tab fits the window's 480 pt.
                .padding(.top, -16)
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

    /// A picker for one edge. Options that cannot be used on this Mac are listed but disabled, with
    /// the reason; the keyboard backlight shows as media control while its bridge is missing. Without Accessibility,
    /// a caption under the title says the chosen action cannot run yet.
    private func edgePicker(_ title: String, action: WritableKeyPath<AppSettings, EdgeAction>) -> some View {
        let available = model.backlightAvailable
        let selection = Binding(
            get: { EdgeChoices.displayed(model.settings[keyPath: action], backlightAvailable: available) },
            set: { model.settings[keyPath: action] = $0 }
        )
        let shown = selection.wrappedValue
        let gated = ConfigMapper.gated(shown, accessibilityTrusted: model.accessibilityGranted) != shown
        return Picker(selection: selection) {
            ForEach(EdgeChoices.all, id: \.self) { choice in
                let name = SettingsLabels.title(for: choice)
                if let caption = EdgeChoices.caption(for: choice, backlightAvailable: available) {
                    Text("\(name) — \(caption)").tag(choice)
                        .disabled(!EdgeChoices.isSelectable(choice, backlightAvailable: available))
                } else {
                    Text(name).tag(choice)
                }
            }
        } label: {
            Text(title)
            if gated {
                Text("Needs Accessibility access")
            }
        }
    }
}
