import SwiftUI
import TrrekAppCore
import TrrekEngine

/// A glass trackpad silhouette with the four edge strips and the four corner badges.
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

    static let size = CGSize(width: 270, height: 180)
    /// The height in the Edges tab, which also holds Edges For and, for an app, its caption and Remove button.
    static let compactHeight: CGFloat = 150
    /// The opacity of the part of the diagram a tab does not edit.
    static let readOnlyOpacity = 0.45
    private static let cornerRadius: CGFloat = 12
    static let stripThickness: CGFloat = 5
    private static let inset: CGFloat = 8
    /// The widest a side edge's label gets: half the diagram less the strip, so the left and right labels never
    /// meet; a longer one wraps onto a second line.
    static let sideLabelWidth: CGFloat = 108

    let settings: AppSettings
    let backlightAvailable: Bool
    let accessibilityGranted: Bool
    var editing: Editing?
    var height: CGFloat = TrackpadDiagram.size.height
    /// The app whose edges the strips show; `nil` for the All Apps edges. Corners are the same for every app.
    var bundleID: String?

    var body: some View {
        GlassEffectContainer {
            ZStack {
                ForEach(TrrekEngine.Edge.allCases, id: \.self) { edge in
                    edgeView(edge)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Self.alignment(of: edge))
                }
                ForEach(Corner.allCases, id: \.self) { corner in
                    badge(for: corner)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Self.alignment(of: corner))
                }
            }
            .padding(Self.inset)
            .frame(width: Self.size.width, height: height)
            .glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Trackpad diagram")
        .onDisappear {
            // The pointer may still be over a menu when the tab goes away; its hover end never comes.
            editing?.model.hoveredDiagramControl = nil
        }
    }

    /// The length of an edge's strip.
    func stripLength(_ edge: TrrekEngine.Edge) -> CGFloat {
        edge == .top || edge == .bottom ? Self.size.width * 0.5 : height * 0.45
    }

    // MARK: - Edges

    @ViewBuilder
    private func edgeView(_ edge: TrrekEngine.Edge) -> some View {
        switch editing {
        case let .edges(model):
            EdgeMenu(model: model, edge: edge, stripLength: stripLength(edge))
        case let .corners(model):
            let item = model.diagramEdge(edge)
            EdgeUnit(item: item, hovered: false, stripLength: stripLength(edge))
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
                stripLength: stripLength(edge)
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
        case let .edges(model):
            let item = model.diagramCorner(corner)
            let alignment = Self.alignment(of: corner)
            CornerBadge(action: item.action, note: item.note, hovered: false, flat: true, alignment: alignment)
                .opacity(Self.readOnlyOpacity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(SettingsLabels.title(for: corner))
                .accessibilityValue(SettingsLabels.title(for: item.action))
        case nil:
            let action = ConfigMapper.gated(settings[corner: corner], accessibilityTrusted: accessibilityGranted)
            CornerBadge(action: action, note: nil, hovered: false, flat: false, alignment: Self.alignment(of: corner))
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

/// An edge's strip with its label beside it, towards the middle of the trackpad. In the Edges tab the whole of it
/// opens the edge's menu.
struct EdgeUnit: View {
    let edge: TrrekEngine.Edge
    let action: EdgeAction
    /// The action whose colour the strip takes (Off, grey, while the edge waits for Accessibility).
    let stripAction: EdgeAction
    let dimmed: Bool
    let inherited: Bool
    let note: DiagramNote?
    let hovered: Bool
    let stripLength: CGFloat

    init(
        edge: TrrekEngine.Edge,
        action: EdgeAction,
        stripAction: EdgeAction,
        dimmed: Bool,
        inherited: Bool,
        note: DiagramNote?,
        hovered: Bool,
        stripLength: CGFloat
    ) {
        self.edge = edge
        self.action = action
        self.stripAction = stripAction
        self.dimmed = dimmed
        self.inherited = inherited
        self.note = note
        self.hovered = hovered
        self.stripLength = stripLength
    }

    /// The edge as the Edges and Corners & Taps tabs show it: the chosen action, grey when it is inherited, off or
    /// waiting for Accessibility.
    init(item: DiagramEdgeItem, hovered: Bool, stripLength: CGFloat) {
        self.init(
            edge: item.edge,
            action: item.action,
            stripAction: item.stripAction,
            dimmed: item.isInherited || item.action == .off || item.note == .needsAccessibility,
            inherited: item.isInherited,
            note: item.note,
            hovered: hovered,
            stripLength: stripLength
        )
    }

    var body: some View {
        Group {
            switch edge {
            case .top:
                VStack(spacing: 4) {
                    strip
                    label
                }
            case .bottom:
                VStack(spacing: 4) {
                    label
                    strip
                }
            case .left:
                HStack(spacing: 4) {
                    strip
                    label.frame(maxWidth: TrackpadDiagram.sideLabelWidth, alignment: .leading)
                }
            case .right:
                HStack(spacing: 4) {
                    label.frame(maxWidth: TrackpadDiagram.sideLabelWidth, alignment: .trailing)
                    strip
                }
            }
        }
        .padding(2)
    }

    private var strip: some View {
        let horizontal = edge == .top || edge == .bottom
        return Capsule()
            .fill(TrackpadDiagram.color(for: stripAction))
            .frame(
                width: horizontal ? stripLength : TrackpadDiagram.stripThickness,
                height: horizontal ? TrackpadDiagram.stripThickness : stripLength
            )
    }

    private var label: some View {
        EdgeLabel(edge: edge, action: action, dimmed: dimmed, inherited: inherited, note: note, hovered: hovered)
    }
}

// MARK: - Labels

/// An edge's symbol and name. Grey when the edge is off, uses the All Apps action (also in italics) or waits for
/// Accessibility; a note adds a warning symbol, and the hover state a chevron and a highlight. A side edge's name may
/// wrap onto a second line; the padding is always there, so the hover highlight does not move the label.
struct EdgeLabel: View {
    let edge: TrrekEngine.Edge
    let action: EdgeAction
    let dimmed: Bool
    /// An app's edge that uses the All Apps action is also set in italics, so it reads differently from Off.
    let inherited: Bool
    let note: DiagramNote?
    let hovered: Bool

    private var wraps: Bool {
        edge == .left || edge == .right
    }

    var body: some View {
        HStack(spacing: 3) {
            if let symbol = SettingsLabels.symbol(for: action) {
                Image(systemName: symbol)
            }
            Text(SettingsLabels.title(for: action))
                .lineLimit(wraps ? 2 : 1)
                .multilineTextAlignment(edge == .right ? .trailing : .leading)
                .fixedSize(horizontal: !wraps, vertical: true)
            if let note {
                NoteSymbol(note: note)
            }
            if hovered {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .italic(inherited)
        .foregroundStyle(dimmed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background {
            if hovered {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            }
        }
        .contentShape(.rect(cornerRadius: 6))
    }
}

/// A small glass badge with the corner action's symbol, or "Off"; a note adds a warning symbol at its outer corner
/// and the hover state a chevron on its inner side. Flat (without glass) where corners cannot be changed.
struct CornerBadge: View {
    let action: CornerAction
    let note: DiagramNote?
    let hovered: Bool
    /// Drawn without its glass, for a tab where corners cannot be changed, so it does not look like a button.
    let flat: Bool
    /// The corner it sits in; the chevron goes on the side towards the middle of the trackpad.
    let alignment: Alignment

    var body: some View {
        HStack(spacing: 3) {
            if hovered, alignment.horizontal == .trailing {
                chevron
            }
            content
            if hovered, alignment.horizontal == .leading {
                chevron
            }
        }
        .padding(.horizontal, 6)
        .frame(minWidth: 34, minHeight: 24)
        .contentShape(.rect(cornerRadius: 12))
        .glassEffect(flat ? .identity : .regular.interactive(hovered), in: .rect(cornerRadius: 12))
        .overlay(alignment: alignment) {
            if let note {
                NoteSymbol(note: note)
                    .font(.system(size: 9))
                    .offset(x: alignment.horizontal == .leading ? -3 : 3, y: alignment.vertical == .top ? -3 : 3)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let symbol = SettingsLabels.symbol(for: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(note == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        } else {
            Text(SettingsLabels.title(for: action))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

/// The warning symbol of a note: orange for missing Accessibility, grey for the keyboard backlight fallback.
private struct NoteSymbol: View {
    let note: DiagramNote

    var body: some View {
        switch note {
        case .needsAccessibility:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .backlightUnavailable:
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
    }
}
