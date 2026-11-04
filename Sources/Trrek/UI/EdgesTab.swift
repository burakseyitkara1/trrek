import SwiftUI
import TrrekAppCore
import TrrekEngine

/// The edge layout: the diagram, the top and bottom actions and the strip geometry.
struct EdgesTab: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $model.settings.swapSides) {
                    Text("Swap Sides")
                    Text("Volume on the left edge, brightness on the right.")
                }
                edgePicker("Top Edge", action: \.topEdge)
                edgePicker("Bottom Edge", action: \.bottomEdge)
            } header: {
                TrackpadDiagram(
                    settings: model.settings,
                    backlightAvailable: model.backlightAvailable,
                    accessibilityGranted: model.accessibilityGranted,
                    interactive: true,
                    onChange: { model.settings = $0 }
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
                Toggle(isOn: $model.settings.externalMonitorBrightness) {
                    Text("External Monitor Brightness")
                    Text(SettingsLabels.externalBrightnessCaption)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// A picker for the top or bottom edge. Options that cannot be used on this Mac are listed but disabled, with
    /// the reason; the keyboard backlight shows as media control while its bridge is missing.
    private func edgePicker(_ title: String, action: WritableKeyPath<AppSettings, EdgeAction>) -> some View {
        let available = model.backlightAvailable
        let selection = Binding(
            get: { EdgeChoices.displayed(model.settings[keyPath: action], backlightAvailable: available) },
            set: { model.settings[keyPath: action] = $0 }
        )
        return Picker(title, selection: selection) {
            ForEach(EdgeChoices.topAndBottom, id: \.self) { choice in
                let name = SettingsLabels.title(for: choice)
                if let caption = EdgeChoices.caption(for: choice, backlightAvailable: available) {
                    Text("\(name) — \(caption)").tag(choice)
                        .disabled(!EdgeChoices.isSelectable(choice, backlightAvailable: available))
                } else {
                    Text(name).tag(choice)
                }
            }
        }
    }
}
