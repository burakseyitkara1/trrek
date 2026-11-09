import SwiftUI
import TrrekAppCore
import TrrekEngine

/// A glass trackpad silhouette with the four edge strips and the four corner badges.
///
/// Read-only by default (the welcome window): the strips and badges show what each edge and corner actually does,
/// so without Accessibility the actions that need it show as off. With `editing`, the edge labels (Edges tab) or the
/// corner badges (Corners & Taps tab) are menus of their actions instead, showing the action chosen for each, with a
/// warning badge on the ones that cannot run as chosen.
struct TrackpadDiagram: View {
    /// Which part of the diagram is a set of menus, and the model they edit.
    enum Editing {
        case edges(SettingsModel)
        case corners(SettingsModel)
    }

    static let size = CGSize(width: 270, height: 180)
    private static let cornerRadius: CGFloat = 12
    private static let stripThickness: CGFloat = 5
    private static let inset: CGFloat = 8
    /// The widest a side edge's label gets: half the diagram less the strip, so the left and right labels never
    /// meet; a longer one wraps onto a second line.
    static let sideLabelWidth: CGFloat = 108

    let settings: AppSettings
    let backlightAvailable: Bool
    let accessibilityGranted: Bool
    var editing: Editing?
    /// The app whose edges the strips show; `nil` for the All Apps edges. Corners are the same for every app.
    var bundleID: String?

    var body: some View {
        let edges = DiagramEdges(
            settings: settings,
            backlightAvailable: backlightAvailable,
            accessibilityTrusted: accessibilityGranted,
            bundleID: bundleID
        )
        GlassEffectContainer {
            ZStack {
                horizontalStrip(.top, action: edges.top)
                horizontalStrip(.bottom, action: edges.bottom)
                verticalStrip(.left, action: edges.left)
                verticalStrip(.right, action: edges.right)
                ForEach(Corner.allCases, id: \.self) { corner in
                    badge(for: corner)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Self.alignment(of: corner))
                }
            }
            .padding(Self.inset)
            .frame(width: Self.size.width, height: Self.size.height)
            .glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Trackpad diagram")
    }

    // MARK: - Edges

    private func horizontalStrip(_ edge: TrrekEngine.Edge, action: EdgeAction) -> some View {
        VStack(spacing: 4) {
            if edge == .bottom {
                Spacer(minLength: 0)
                edgeLabel(edge, action: action)
            }
            Capsule()
                .fill(stripColor(edge, action: action))
                .frame(width: Self.size.width * 0.5, height: Self.stripThickness)
            if edge == .top {
                edgeLabel(edge, action: action)
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 2)
    }

    private func verticalStrip(_ edge: TrrekEngine.Edge, action: EdgeAction) -> some View {
        HStack(spacing: 4) {
            if edge == .right {
                Spacer(minLength: 0)
                edgeLabel(edge, action: action)
                    .frame(maxWidth: Self.sideLabelWidth, alignment: .trailing)
            }
            Capsule()
                .fill(stripColor(edge, action: action))
                .frame(width: Self.stripThickness, height: Self.size.height * 0.45)
            if edge == .left {
                edgeLabel(edge, action: action)
                    .frame(maxWidth: Self.sideLabelWidth, alignment: .leading)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func edgeLabel(_ edge: TrrekEngine.Edge, action: EdgeAction) -> some View {
        if case let .edges(model) = editing {
            EdgeMenu(model: model, edge: edge)
        } else {
            EdgeLabel(edge: edge, action: action, dimmed: action == .off, note: nil, hovered: false)
        }
    }

    /// The edge's colour; grey while an edge being edited waits for Accessibility, since it does not run.
    private func stripColor(_ edge: TrrekEngine.Edge, action: EdgeAction) -> Color {
        guard case let .edges(model) = editing else { return Self.color(for: action) }
        let item = model.diagramEdge(edge)
        return item.note == .needsAccessibility ? Self.color(for: .off) : Self.color(for: item.action)
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
        if case let .corners(model) = editing {
            CornerMenu(model: model, corner: corner)
        } else {
            let action = ConfigMapper.gated(settings[corner: corner], accessibilityTrusted: accessibilityGranted)
            CornerBadge(action: action, note: nil, hovered: false, alignment: Self.alignment(of: corner))
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

// MARK: - Labels

/// An edge's symbol and name. Grey when the edge is off, uses the All Apps action or waits for Accessibility; a
/// note adds a warning symbol, and the hover state a chevron and a highlight. A side edge's name may wrap onto a
/// second line; the padding is always there, so the hover highlight does not move the label.
struct EdgeLabel: View {
    let edge: TrrekEngine.Edge
    let action: EdgeAction
    let dimmed: Bool
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
/// and the hover state a chevron on its inner side.
struct CornerBadge: View {
    let action: CornerAction
    let note: DiagramNote?
    let hovered: Bool
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
        .glassEffect(.regular.interactive(hovered), in: .rect(cornerRadius: 12))
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
