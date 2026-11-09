import SwiftUI
import TrrekAppCore
import TrrekEngine

/// An edge (its zone and label) as a menu of the edge actions, Off first; for an app, Same as All Apps comes before
/// Off. A divider follows each of them.
struct EdgeMenu: View {
    let model: SettingsModel
    let edge: TrrekEngine.Edge
    let zones: DiagramZones

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
                    if option.action == nil || option.action == .off {
                        Divider()
                    }
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            // The zone and the label set their own hit areas (`EdgeUnit`).
            EdgeUnit(item: item, active: model.hoveredDiagramControl == .edge(edge), zones: zones)
        }
        .diagramMenu(model: model, control: .edge(edge))
        .help(DiagramHelp.text(title: SettingsLabels.title(for: edge), value: item.valueTitle, notes: item.notes))
        .accessibilityLabel(SettingsLabels.title(for: edge))
        .accessibilityValue(item.valueTitle)
        .accessibilityHint(DiagramHelp.hint(item.notes))
    }
}

/// A corner's badge as a menu of the corner actions, Off first. The menu also opens from a margin around the badge,
/// so the small badge is easy to hit.
struct CornerMenu: View {
    let model: SettingsModel
    let corner: Corner
    private static let hitMargin: CGFloat = 6

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
                    if action == .off {
                        Divider()
                    }
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
            .padding(Self.hitMargin)
            .contentShape(.rect)
        }
        .diagramMenu(model: model, control: .corner(corner))
        // The margin reaches past the badge's place, so the badge stays where it is.
        .padding(-Self.hitMargin)
        .help(DiagramHelp.text(
            title: SettingsLabels.title(for: corner),
            value: SettingsLabels.title(for: item.action),
            notes: item.note.map { [$0] } ?? []
        ))
        .accessibilityLabel(SettingsLabels.title(for: corner))
        .accessibilityValue(SettingsLabels.title(for: item.action))
        .accessibilityHint(DiagramHelp.hint(item.note.map { [$0] } ?? []))
    }
}

/// The tooltip and accessibility hint of an edge or corner.
private enum DiagramHelp {
    /// "Left Edge: Brightness", then a line for each reason it does not run as chosen.
    static func text(title: String, value: String, notes: [DiagramNote]) -> String {
        (["\(title): \(value)"] + notes.map(\.text)).joined(separator: "\n")
    }

    /// Every reason it does not run as chosen, one sentence each; empty when it runs.
    static func hint(_ notes: [DiagramNote]) -> String {
        notes.map(\.text).joined(separator: ". ")
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
