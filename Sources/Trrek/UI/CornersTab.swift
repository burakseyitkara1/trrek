import SwiftUI
import TrrekAppCore
import TrrekEngine

/// Corner double-tap actions and the three-finger middle click.
struct CornersTab: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section {
                ForEach(Corner.allCases, id: \.self) { corner in
                    Picker(SettingsLabels.title(for: corner), selection: binding(for: corner)) {
                        ForEach(CornerAction.allCases, id: \.self) { action in
                            Text(SettingsLabels.title(for: action)).tag(action)
                        }
                    }
                }
            } header: {
                TrackpadDiagram(
                    settings: model.settings,
                    backlightAvailable: model.backlightAvailable,
                    accessibilityGranted: model.accessibilityGranted,
                    interactive: true,
                    onChange: { model.settings = $0 }
                )
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
            } footer: {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(isOn: $model.settings.middleClick) {
                    Text("3-Finger Tap Middle Click")
                    Text("Set Look up & data detectors to Force click with one finger in System Settings › Trackpad")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var footer: String {
        model.accessibilityGranted
            ? String(
                localized: "Double-tap a corner to run its action. Click a corner in the diagram to change it.",
                bundle: .main
            )
            : String(
                localized: "Double-tap a corner to run its action once Accessibility access is granted.",
                bundle: .main
            )
    }

    private func binding(for corner: Corner) -> Binding<CornerAction> {
        Binding(
            get: { model.settings[corner: corner] },
            set: { model.settings[corner: corner] = $0 }
        )
    }
}
