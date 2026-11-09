import SwiftUI
import TrrekAppCore
import TrrekEngine

/// An edge's label as a menu of the edge actions; for an app, Same as All Apps comes first.
struct EdgeMenu: View {
    let model: SettingsModel
    let edge: TrrekEngine.Edge

    var body: some View {
        let item = model.diagramEdge(edge)
        let options = model.edgeMenuOptions(for: edge)
        let selection = Binding(
            get: { model.edgeMenuSelection(for: edge) },
            set: { model.chooseEdgeAction($0, for: edge) }
        )
        Menu {
            Picker(selection: selection) {
                ForEach(options) { option in
                    Label {
                        Text(option.title)
                    } icon: {
                        if let symbol = option.symbol {
                            Image(systemName: symbol)
                        }
                    }
                    .tag(option.action)
                    .disabled(!option.isEnabled)
                    if option.action == nil {
                        Divider()
                    }
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            EdgeLabel(
                edge: edge,
                action: item.action,
                dimmed: item.isInherited || item.action == .off || item.note == .needsAccessibility,
                note: item.note,
                hovered: model.hoveredDiagramControl == .edge(edge)
            )
        }
        .diagramMenu(model: model, control: .edge(edge))
        .help(DiagramHelp.text(title: SettingsLabels.title(for: edge), value: item.valueTitle, note: item.note))
        .accessibilityLabel(SettingsLabels.title(for: edge))
        .accessibilityValue(item.valueTitle)
        .accessibilityHint(item.note?.text ?? "")
    }
}

/// A corner's badge as a menu of the corner actions, Off first.
struct CornerMenu: View {
    let model: SettingsModel
    let corner: Corner

    var body: some View {
        let item = model.diagramCorner(corner)
        let selection = Binding(
            get: { model.settings[corner: corner] },
            set: { model.chooseCornerAction($0, for: corner) }
        )
        Menu {
            Picker(selection: selection) {
                ForEach(model.cornerMenuOptions, id: \.self) { action in
                    Label {
                        Text(SettingsLabels.title(for: action))
                    } icon: {
                        if let symbol = SettingsLabels.symbol(for: action) {
                            Image(systemName: symbol)
                        }
                    }
                    .tag(action)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            CornerBadge(
                action: item.action,
                note: item.note,
                hovered: model.hoveredDiagramControl == .corner(corner),
                alignment: TrackpadDiagram.alignment(of: corner)
            )
        }
        .diagramMenu(model: model, control: .corner(corner))
        .help(DiagramHelp.text(
            title: SettingsLabels.title(for: corner),
            value: SettingsLabels.title(for: item.action),
            note: item.note
        ))
        .accessibilityLabel(SettingsLabels.title(for: corner))
        .accessibilityValue(SettingsLabels.title(for: item.action))
        .accessibilityHint(item.note?.text ?? "")
    }
}

/// The tooltip of an edge or corner: "Left Edge: Brightness", and on a second line why it does not run as chosen.
private enum DiagramHelp {
    static func text(title: String, value: String, note: DiagramNote?) -> String {
        let line = "\(title): \(value)"
        guard let note else { return line }
        return line + "\n" + note.text
    }
}

private extension View {
    /// A borderless menu whose label is the diagram's own drawing, with the pointing hand and the hover state.
    func diagramMenu(model: SettingsModel, control: DiagramControl) -> some View {
        menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            .pointerStyle(.link)
            .onHover { hovering in
                if hovering {
                    model.hoveredDiagramControl = control
                } else if model.hoveredDiagramControl == control {
                    model.hoveredDiagramControl = nil
                }
            }
    }
}

/// The diagram at the top of the Edges and Corners & Taps tabs, a line on how to change an action, and, while an
/// action shown waits for Accessibility access, why it does not run yet.
struct DiagramHeader: View {
    let diagram: TrackpadDiagram
    let caption: String
    let needsAccessibility: Bool

    var body: some View {
        VStack(spacing: 6) {
            diagram
            Text(caption)
            if needsAccessibility {
                Label {
                    Text(SettingsLabels.accessibilityNeeded)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }
}
