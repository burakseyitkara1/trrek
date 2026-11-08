import SwiftUI
import TrrekAppCore
import TrrekEngine
import TrrekPlatform

/// Feedback, slide behaviour, login item, language, updates, export and import, and reset. The form scrolls when it is
/// taller than the window.
struct GeneralTab: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            if !model.accessibilityGranted {
                Section {
                    Label {
                        Text(SettingsLabels.accessibilityNeeded)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
            }
            Section {
                Picker("Haptic Feedback", selection: $model.settings.hapticStrength) {
                    ForEach(HapticStrength.allCases, id: \.self) { strength in
                        Text(SettingsLabels.title(for: strength)).tag(strength)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section {
                Picker(selection: $model.settings.slideSensitivity) {
                    ForEach(SlideSensitivity.allCases, id: \.self) { sensitivity in
                        Text(SettingsLabels.title(for: sensitivity)).tag(sensitivity)
                    }
                } label: {
                    Text("Slide Sensitivity")
                    Text("Higher sensitivity takes a shorter slide for each step.")
                }
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
                Picker("Language", selection: $model.settings.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.title).tag(language)
                    }
                }
                if model.needsRelaunch {
                    relaunchRow
                }
            }
            Section {
                Toggle(isOn: $model.settings.checkForUpdatesAutomatically) {
                    Text("Check for Updates Automatically")
                    Text("At most once a day; the request carries only trrek’s version.")
                }
                HStack {
                    Text(verbatim: "trrek \(TrrekVersion.string)")
                    Spacer()
                    if model.isCheckingForUpdates {
                        ProgressView().controlSize(.small)
                    }
                    Button("Check Now") { model.checkForUpdatesNow() }
                        .disabled(model.isUpdateBusy || model.isCheckingForUpdates)
                }
                if let row = model.updateRow {
                    UpdateRowLine(row: row) { model.updateNow() }
                }
            } footer: {
                Text(model.updateCheckStatus)
            }
            Section {
                SettingsTransferButtons(model: model)
            } footer: {
                Text("Settings are saved as a .trrek file. Launch at Login and the language are not included.")
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
            Text("Launch at Login and the language keep their current settings.")
        }
    }

    /// Shown while the chosen language differs from the one in use.
    private var relaunchRow: some View {
        HStack {
            Label {
                Text("Relaunch trrek to use the new language.")
            } icon: {
                Image(systemName: "globe")
            }
            .foregroundStyle(.secondary)
            Spacer()
            if model.canRelaunch {
                Button("Relaunch") { model.relaunch() }
            }
        }
    }

    private var freezeCursorCaption: String {
        model.accessibilityGranted
            ? String(localized: "The pointer stays still while you slide along an edge.", bundle: .main)
            : String(localized: "Needs Accessibility access.", bundle: .main)
    }
}

/// The known update in General: its state, the download's progress and the button that starts (or retries) it.
private struct UpdateRowLine: View {
    let row: UpdateRowState
    let action: () -> Void

    var body: some View {
        HStack {
            Text(verbatim: row.statusText)
            Spacer()
            switch row {
            case let .downloading(_, progress?):
                ProgressView(value: progress).frame(width: 80)
            case .downloading, .installing:
                ProgressView().controlSize(.small)
            case .available, .failed, .browser, .relaunch:
                EmptyView()
            }
            if let title = row.actionTitle {
                Button(title, action: action)
            }
        }
    }
}
