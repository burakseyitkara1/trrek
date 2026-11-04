import SwiftUI
import TrrekAppCore

/// The settings window's content: four tabs, each a grouped form.
struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            Tab(SettingsTab.general.title, systemImage: SettingsTab.general.symbol, value: SettingsTab.general) {
                GeneralTab(model: model)
            }
            Tab(SettingsTab.edges.title, systemImage: SettingsTab.edges.symbol, value: SettingsTab.edges) {
                EdgesTab(model: model)
            }
            Tab(SettingsTab.corners.title, systemImage: SettingsTab.corners.symbol, value: SettingsTab.corners) {
                CornersTab(model: model)
            }
            Tab(SettingsTab.advanced.title, systemImage: SettingsTab.advanced.symbol, value: SettingsTab.advanced) {
                AdvancedTab(model: model)
            }
        }
        .frame(width: SettingsWindowController.contentSize.width, height: SettingsWindowController.contentSize.height)
    }
}
