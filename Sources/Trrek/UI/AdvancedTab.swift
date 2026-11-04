import AppKit
import SwiftUI
import TrrekAppCore
import TrrekEngine
import TrrekPlatform

/// Hold-to-slide, paused apps, Accessibility status and version.
struct AdvancedTab: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Picker(selection: $model.settings.holdKey) {
                    ForEach(HoldKey.allCases, id: \.self) { key in
                        Text(SettingsLabels.title(for: key)).tag(key)
                    }
                } label: {
                    Text("Hold-to-Slide Key")
                    Text("Edges respond only while this key is held, or after it is pressed once in Toggle mode.")
                }
                Picker("Mode", selection: $model.settings.holdKeyMode) {
                    ForEach(HoldKeyMode.allCases, id: \.self) { mode in
                        Text(SettingsLabels.title(for: mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(model.settings.holdKey == .none)
            }
            Section("Paused Apps") {
                PausedAppsList(model: model)
            }
            Section {
                accessibilityRow
            }
            Section {
                LabeledContent("Version", value: Self.version)
            }
        }
        .formStyle(.grouped)
    }

    private var accessibilityRow: some View {
        LabeledContent {
            Button("Open System Settings") {
                if let url = Permissions.accessibilityPaneURL {
                    NSWorkspace.shared.open(url)
                }
            }
        } label: {
            if model.accessibilityGranted {
                Label {
                    Text("Accessibility access granted")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            } else {
                Label {
                    Text("Accessibility access needed")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            if !model.accessibilityGranted {
                Text(SettingsLabels.accessibilityNeeded)
            }
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? TrrekVersion.string
        guard let build = info?["CFBundleVersion"] as? String else { return short }
        return "\(short) (\(build))"
    }
}
