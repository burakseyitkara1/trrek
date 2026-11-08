import AppKit
import SwiftUI

/// The apps trrek pauses in while they are in front: one row per app with its icon and name, "+" to add apps
/// from the app chooser and "−" to remove the selected row.
struct PausedAppsList: View {
    @Bindable var model: SettingsModel

    var body: some View {
        if model.settings.pausedBundleIDs.isEmpty {
            Text("No paused apps")
                .foregroundStyle(.secondary)
        }
        ForEach(model.settings.pausedBundleIDs, id: \.self) { bundleID in
            row(for: bundleID)
        }
        HStack(spacing: 12) {
            Button(action: addApps) {
                Image(systemName: "plus")
            }
            .help("Add apps")
            .accessibilityLabel("Add apps")
            Button(action: removeSelected) {
                Image(systemName: "minus")
            }
            .disabled(model.selectedPausedApp == nil)
            .help("Remove the selected app")
            .accessibilityLabel("Remove the selected app")
            Spacer()
            Text("Edges are paused while one of these apps is in front.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
    }

    private func row(for bundleID: String) -> some View {
        let app = model.appInfo(for: bundleID)
        let selected = model.selectedPausedApp == bundleID
        return HStack(spacing: 8) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 20, height: 20)
            Text(app.name)
            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Color.accentColor.opacity(0.25) : .clear)
        )
        .contentShape(.rect)
        .onTapGesture { model.selectedPausedApp = selected ? nil : bundleID }
        .help(bundleID)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    private func addApps() {
        let model = model
        AppChooser.choose(
            title: String(localized: "Choose Apps to Pause In", bundle: .main),
            allowsMultipleSelection: true,
            model: model
        ) { model.addPausedApps(at: $0) }
    }

    private func removeSelected() {
        guard let selection = model.selectedPausedApp else { return }
        model.settings.pausedBundleIDs.removeAll { $0 == selection }
        model.selectedPausedApp = nil
    }
}
