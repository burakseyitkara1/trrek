import SwiftUI
import TrrekAppCore
import TrrekEngine

/// Corner double-tap actions, set with the diagram's corner badges, and the three-finger middle click.
struct CornersTab: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $model.settings.middleClick) {
                    Text("3-Finger Tap Middle Click")
                    Text("Set Look up & data detectors to Force click with one finger in System Settings › Trackpad")
                }
            } header: {
                DiagramHeader(
                    diagram: TrackpadDiagram(
                        settings: model.settings,
                        backlightAvailable: model.backlightAvailable,
                        accessibilityGranted: model.accessibilityGranted,
                        editing: .corners(model),
                        trackpad: model.diagramTrackpad
                    ),
                    caption: String(
                        localized: "Double-tap a corner to run its action. Click a corner in the diagram to change it.",
                        bundle: .main
                    ),
                    needsAccessibility: model.diagramCornersNeedAccessibility
                )
            }
        }
        .formStyle(.grouped)
    }
}
