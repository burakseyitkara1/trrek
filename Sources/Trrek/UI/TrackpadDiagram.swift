import SwiftUI
import TrrekAppCore
import TrrekEngine

/// A glass trackpad silhouette with the four edge zones, to scale, and the four corner badges.
///
/// Each edge's touch zone is a tinted band along it, as thick as the edge width on the trackpad (`DiagramZones`), with
/// the edge's coloured line in it and its label beside it; the corners are the squares where two zones meet. With
/// Bottom Quarter Only the side zones are filled only in their lower quarter. A change of either setting animates.
///
/// Read-only by default (the welcome window): the strips and badges show what each edge and corner actually does,
/// so without Accessibility the actions that need it show as off. With `editing`, the edges (Edges tab) or the
/// corner badges (Corners & Taps tab) are menus of their actions instead. Both parts then show the action chosen for
/// each edge and corner, with a badge on the ones that cannot run as chosen; the part the tab does not edit is faded,
/// and its corner badges lose their glass, so only the menus look clickable.
struct TrackpadDiagram: View {
    /// Which part of the diagram is a set of menus, and the model they edit.
    enum Editing {
        case edges(SettingsModel)
        case corners(SettingsModel)

        var model: SettingsModel {
            switch self {
            case let .edges(model), let .corners(model): model
            }
        }
    }

    /// The largest the diagram gets; its height follows the trackpad's aspect ratio up to this.
    static let size = CGSize(width: 270, height: 180)
    /// The largest height in the Edges tab, which also holds Edges For and, for an app, its caption and Remove button.
    static let compactHeight: CGFloat = 138
    /// The opacity of the part of the diagram a tab does not edit.
    static let readOnlyOpacity = 0.45
    private static let cornerRadius: CGFloat = 12
    /// How far the corner badges sit from the diagram's edges.
    private static let inset: CGFloat = 8

    let settings: AppSettings
    let backlightAvailable: Bool
    let accessibilityGranted: Bool
    var editing: Editing?
    var maxHeight: CGFloat = TrackpadDiagram.size.height
    /// The app whose edges the zones show; `nil` for the All Apps edges. Corners are the same for every app.
    var bundleID: String?
    /// The trackpad the zones are drawn to scale with.
    var trackpad: TrackpadSize = .typical

    /// The zones for the settings' edge width and Bottom Quarter Only.
    var zones: DiagramZones {
        DiagramZones(
            trackpad: trackpad,
            edgeWidthMM: CGFloat(settings.edgeWidth.millimetres),
            bottomQuarterOnly: settings.bottomQuarterOnly,
            width: Self.size.width,
            maxHeight: maxHeight
        )
    }

    var body: some View {
        let zones = zones
        GlassEffectContainer {
            ZStack {
                cornerZones(zones)
                ForEach(TrrekEngine.Edge.allCases, id: \.self) { edge in
                    edgeView(edge, zones: zones)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Self.alignment(of: edge))
                }
                ZStack {
                    ForEach(Corner.allCases, id: \.self) { corner in
                        badge(for: corner)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Self.alignment(of: corner))
                    }
                }
                .padding(Self.inset)
            }
            .frame(width: zones.size.width, height: zones.size.height)
            .animation(.smooth, value: zones)
            .glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Trackpad diagram")
        .onDisappear {
            // The pointer may still be over a menu when the tab goes away; its hover end never comes.
            editing?.model.hoveredDiagramControl = nil
        }
    }

    /// The corner zones, a neutral tint a little stronger than the edge zones; faded with the corner badges in the
    /// Edges tab.
    private func cornerZones(_ zones: DiagramZones) -> some View {
        ZStack {
            ForEach(Corner.allCases, id: \.self) { corner in
                Rectangle()
                    .fill(.primary.opacity(0.16))
                    .frame(width: zones.cornerSize.width, height: zones.cornerSize.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Self.alignment(of: corner))
            }
        }
        .clipShape(.rect(cornerRadius: Self.cornerRadius))
        .opacity(editsEdges ? Self.readOnlyOpacity : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var editsEdges: Bool {
        if case .edges = editing {
            true
        } else {
            false
        }
    }

    // MARK: - Edges

    @ViewBuilder
    private func edgeView(_ edge: TrrekEngine.Edge, zones: DiagramZones) -> some View {
        switch editing {
        case let .edges(model):
            EdgeMenu(model: model, edge: edge, zones: zones)
        case let .corners(model):
            let item = model.diagramEdge(edge)
            EdgeUnit(item: item, hovered: false, zones: zones)
                .opacity(Self.readOnlyOpacity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(SettingsLabels.title(for: edge))
                .accessibilityValue(item.valueTitle)
        case nil:
            let edges = DiagramEdges(
                settings: settings,
                backlightAvailable: backlightAvailable,
                accessibilityTrusted: accessibilityGranted,
                bundleID: bundleID
            )
            let action = Self.action(of: edge, in: edges)
            EdgeUnit(
                edge: edge,
                action: action,
                stripAction: action,
                dimmed: action == .off,
                inherited: false,
                note: nil,
                hovered: false,
                zones: zones
            )
        }
    }

    private static func action(of edge: TrrekEngine.Edge, in edges: DiagramEdges) -> EdgeAction {
        switch edge {
        case .left: edges.left
        case .right: edges.right
        case .top: edges.top
        case .bottom: edges.bottom
        }
    }

    private static func alignment(of edge: TrrekEngine.Edge) -> Alignment {
        switch edge {
        case .left: .leading
        case .right: .trailing
        case .top: .top
        case .bottom: .bottom
        }
    }

    // A flat, exhaustive mapping reads best as one switch.
    // swiftlint:disable:next cyclomatic_complexity
    static func color(for action: EdgeAction) -> Color {
        switch action {
        case .volume: .blue
        case .brightness: .yellow
        case .keyboardBacklight: .orange
        case .switchApps: .purple
        case .switchTabs: .indigo
        case .switchDesktops: .cyan
        case .scrubVideo: .teal
        case .media: .green
        case .zoom: .pink
        case .undoRedo: .brown
        case .off: .gray
        }
    }

    // MARK: - Corners

    @ViewBuilder
    private func badge(for corner: Corner) -> some View {
        switch editing {
        case let .corners(model):
            CornerMenu(model: model, corner: corner)
        case .edges:
            // The Edges tab does not edit corners: only their faded zones show, no labels, which would not fit the
            // corner squares at Narrow and would cross the edge zones.
            EmptyView()
        case nil:
            let action = ConfigMapper.gated(settings[corner: corner], accessibilityTrusted: accessibilityGranted)
            CornerBadge(action: action, note: nil, hovered: false, alignment: Self.alignment(of: corner))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(SettingsLabels.title(for: corner))
                .accessibilityValue(SettingsLabels.title(for: action))
        }
    }

    static func alignment(of corner: Corner) -> Alignment {
        switch corner {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
    }
}
