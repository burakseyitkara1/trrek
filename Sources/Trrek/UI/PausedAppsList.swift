import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The apps trrek pauses in while they are in front: one row per app with its icon and name, "+" to add apps
/// from an open panel and "−" to remove the selected row.
struct PausedAppsList: View {
    @Binding var bundleIDs: [String]
    @Binding var selection: String?

    var body: some View {
        if bundleIDs.isEmpty {
            Text("No paused apps")
                .foregroundStyle(.secondary)
        }
        ForEach(bundleIDs, id: \.self) { bundleID in
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
            .disabled(selection == nil)
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
        let app = AppInfo(bundleID: bundleID)
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
                .fill(selection == bundleID ? Color.accentColor.opacity(0.25) : .clear)
        )
        .contentShape(.rect)
        .onTapGesture { selection = selection == bundleID ? nil : bundleID }
        .help(bundleID)
        .accessibilityAddTraits(selection == bundleID ? [.isSelected, .isButton] : .isButton)
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.title = "Choose Apps to Pause In"
        panel.prompt = "Add"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier, !bundleIDs.contains(id) else { continue }
            bundleIDs.append(id)
        }
    }

    private func removeSelected() {
        guard let selection else { return }
        bundleIDs.removeAll { $0 == selection }
        self.selection = nil
    }
}

/// The name and icon of an installed app; falls back to the bundle ID and a generic icon when it is not found.
private struct AppInfo {
    let name: String
    let icon: NSImage

    init(bundleID: String) {
        let workspace = NSWorkspace.shared
        guard let url = workspace.urlForApplication(withBundleIdentifier: bundleID) else {
            name = bundleID
            icon = workspace.icon(for: .applicationBundle)
            return
        }
        let displayName = FileManager.default.displayName(atPath: url.path)
        name = displayName.hasSuffix(".app") ? String(displayName.dropLast(4)) : displayName
        icon = workspace.icon(forFile: url.path)
    }
}
