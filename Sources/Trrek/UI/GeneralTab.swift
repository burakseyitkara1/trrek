import SwiftUI
import TrrekAppCore
import TrrekPlatform

/// Feedback, slide behaviour, login item and reset.
struct GeneralTab: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Picker("Haptic Feedback", selection: $model.settings.hapticStrength) {
                    ForEach(HapticStrength.allCases, id: \.self) { strength in
                        Text(SettingsLabels.title(for: strength)).tag(strength)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section {
                Toggle(isOn: $model.settings.precision) {
                    Text("Precision Control")
                    Text("Each step changes the level by a quarter as much.")
                }
                Toggle(isOn: $model.settings.freezeCursor) {
                    Text("Freeze Cursor")
                    Text(freezeCursorCaption)
                }
            }
            Section {
                Toggle("Launch at Login", isOn: $model.settings.launchAtLogin)
            }
            Section {
                HStack {
                    Spacer()
                    Button("Reset to Defaults…") { model.confirmingReset = true }
                }
            }
        }
        .formStyle(.grouped)
        .alert("Reset all settings to their defaults?", isPresented: $model.confirmingReset) {
            Button("Reset", role: .destructive) { model.resetToDefaults() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Launch at Login keeps its current setting.")
        }
    }

    private var freezeCursorCaption: String {
        model.accessibilityGranted
            ? "The pointer stays still while you slide along an edge."
            : "Needs Accessibility access."
    }
}
