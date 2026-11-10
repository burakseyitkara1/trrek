import SwiftUI
import TrrekAppCore
import TrrekEngine

/// The look of the diagram's zones: calm and neutral at rest, in the system accent colour where the pointer is.
enum DiagramStyle {
    /// An edge zone at rest: the same neutral tint on every edge.
    static let zone = AnyShapeStyle(.fill.secondary)
    /// A corner zone at rest: a little stronger than the edge zones.
    static let corner = AnyShapeStyle(.fill)
    /// The part of a side zone that does not start slides (Bottom Quarter Only).
    static let inactiveZone = AnyShapeStyle(.fill.quaternary)
    static let inactiveOutline = AnyShapeStyle(.tertiary)
    /// A zone under the pointer.
    static let activeZone = AnyShapeStyle(Color.accentColor.opacity(0.22))
    /// The ring around a corner badge under the pointer. Not a glass tint: glass tints turn grey while the window is
    /// inactive, and the pointer lights the diagram up in an inactive window too.
    static let activeRingWidth: CGFloat = 1.5
    /// The line along the outer edge of an active zone.
    static let activeLineThickness: CGFloat = 2
}

/// An edge's zone, a neutral band along the edge, and its label just inside it, towards the middle of the trackpad.
/// While the edge is active (under the pointer in the Edges tab) its band turns to the accent colour with an accent
/// line along the trackpad's edge, and its label becomes an accent pill. In the Edges tab the zone and the label open
/// the edge's menu; the space around the label does not, since a side zone runs past the top and bottom labels.
struct EdgeUnit: View {
    let edge: TrrekEngine.Edge
    let action: EdgeAction
    let dimmed: Bool
    let inherited: Bool
    let note: DiagramNote?
    let active: Bool
    let zones: DiagramZones

    init(
        edge: TrrekEngine.Edge,
        action: EdgeAction,
        dimmed: Bool,
        inherited: Bool,
        note: DiagramNote?,
        active: Bool,
        zones: DiagramZones
    ) {
        self.edge = edge
        self.action = action
        self.dimmed = dimmed
        self.inherited = inherited
        self.note = note
        self.active = active
        self.zones = zones
    }

    /// The edge as the Edges and Corners & Taps tabs show it: the chosen action, grey when it is inherited, off or
    /// waiting for Accessibility.
    init(item: DiagramEdgeItem, active: Bool, zones: DiagramZones) {
        self.init(
            edge: item.edge,
            action: item.action,
            dimmed: item.isInherited || item.action == .off || item.note == .needsAccessibility,
            inherited: item.isInherited,
            note: item.note,
            active: active,
            zones: zones
        )
    }

    var body: some View {
        let gap = DiagramZones.labelGap
        switch edge {
        case .top:
            VStack(spacing: 0) {
                band
                label.padding(.top, gap)
            }
        case .bottom:
            VStack(spacing: 0) {
                label.padding(.bottom, gap)
                band
            }
        case .left:
            HStack(spacing: 0) {
                band
                label
                    .frame(maxWidth: zones.sideLabelWidth, alignment: .leading)
                    .padding(.leading, gap)
            }
        case .right:
            HStack(spacing: 0) {
                label
                    .frame(maxWidth: zones.sideLabelWidth, alignment: .trailing)
                    .padding(.trailing, gap)
                band
            }
        }
    }

    /// The zone between its corners. A side zone with Bottom Quarter Only is filled only in its lower part, which
    /// starts slides; above it the zone is faint with a dashed outline, and stays neutral while the edge is active.
    @ViewBuilder
    private var band: some View {
        switch edge {
        case .top, .bottom:
            activeArea
                .frame(width: zones.endLength, height: zones.endThickness)
                .contentShape(.rect)
        case .left, .right:
            VStack(spacing: 0) {
                Rectangle()
                    .fill(DiagramStyle.inactiveZone)
                    .overlay {
                        Rectangle()
                            .strokeBorder(DiagramStyle.inactiveOutline, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    .frame(height: zones.inactiveSideLength)
                    .opacity(zones.inactiveSideLength > 0 ? 1 : 0)
                activeArea
                    .frame(height: zones.activeSideLength)
            }
            .frame(width: zones.sideThickness, height: zones.sideLength)
            .contentShape(.rect)
        }
    }

    /// The part of the zone that starts slides, with the accent line along the trackpad's edge while active.
    private var activeArea: some View {
        Rectangle()
            .fill(active ? DiagramStyle.activeZone : DiagramStyle.zone)
            .overlay(alignment: outerEdge) {
                if active {
                    let thickness = DiagramStyle.activeLineThickness
                    let horizontal = edge == .top || edge == .bottom
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: horizontal ? nil : thickness, height: horizontal ? thickness : nil)
                }
            }
    }

    private var outerEdge: Alignment {
        switch edge {
        case .left: .leading
        case .right: .trailing
        case .top: .top
        case .bottom: .bottom
        }
    }

    private var label: some View {
        EdgeLabel(edge: edge, action: action, dimmed: dimmed, inherited: inherited, note: note, active: active)
    }
}

// MARK: - Labels

/// An edge's symbol and name in the primary text colour; secondary when the edge is off, uses the All Apps action
/// (also in italics) or waits for Accessibility. A note adds a warning symbol. While the edge is active the label is an
/// accent pill with a chevron inside. A side edge's name may wrap onto a second line; the padding is always there, so
/// the pill does not move the label.
struct EdgeLabel: View {
    let edge: TrrekEngine.Edge
    let action: EdgeAction
    let dimmed: Bool
    /// An app's edge that uses the All Apps action is also set in italics, so it reads differently from Off.
    let inherited: Bool
    let note: DiagramNote?
    let active: Bool

    private var wraps: Bool {
        edge == .left || edge == .right
    }

    private var textStyle: AnyShapeStyle {
        if active {
            AnyShapeStyle(.white)
        } else if dimmed {
            AnyShapeStyle(.secondary)
        } else {
            AnyShapeStyle(.primary)
        }
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
                NoteSymbol(note: note, onAccent: active)
            }
            if active {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
        }
        .font(.caption)
        .italic(inherited)
        .foregroundStyle(textStyle)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background {
            if active {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor)
            }
        }
        .contentShape(.rect(cornerRadius: 8))
    }
}

/// A small glass badge with the corner action's symbol, or "Off"; a note adds a warning symbol at its outer corner
/// and the hover state an accent ring, accent content and a chevron on its inner side.
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
        .overlay {
            if hovered {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: DiagramStyle.activeRingWidth)
            }
        }
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
                .foregroundStyle(contentStyle(dimmed: note != nil))
        } else {
            Text(SettingsLabels.title(for: action))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(contentStyle(dimmed: true))
        }
    }

    /// The accent colour under the pointer, since the badge covers most of its lit corner zone; otherwise primary, or
    /// secondary for Off and a gated action.
    private func contentStyle(dimmed: Bool) -> AnyShapeStyle {
        if hovered {
            AnyShapeStyle(Color.accentColor)
        } else if dimmed {
            AnyShapeStyle(.secondary)
        } else {
            AnyShapeStyle(.primary)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(contentStyle(dimmed: true))
    }
}

/// The warning symbol of a note: orange for missing Accessibility, grey for the keyboard backlight fallback (white on
/// an accent pill).
private struct NoteSymbol: View {
    let note: DiagramNote
    var onAccent = false

    var body: some View {
        switch note {
        case .needsAccessibility:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .backlightUnavailable:
            Image(systemName: "info.circle")
                .foregroundStyle(onAccent ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
        }
    }
}
