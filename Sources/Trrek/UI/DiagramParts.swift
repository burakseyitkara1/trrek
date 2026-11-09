import SwiftUI
import TrrekAppCore
import TrrekEngine

/// An edge's zone, a band in its colour with the coloured line in it, and its label beside it, towards the middle
/// of the trackpad. In the Edges tab the zone and the label open the edge's menu; the space around the label does
/// not, since a side zone runs past the top and bottom labels.
struct EdgeUnit: View {
    let edge: TrrekEngine.Edge
    let action: EdgeAction
    /// The action whose colour the strip takes (Off, grey, while the edge waits for Accessibility).
    let stripAction: EdgeAction
    let dimmed: Bool
    let inherited: Bool
    let note: DiagramNote?
    let hovered: Bool
    let zones: DiagramZones

    init(
        edge: TrrekEngine.Edge,
        action: EdgeAction,
        stripAction: EdgeAction,
        dimmed: Bool,
        inherited: Bool,
        note: DiagramNote?,
        hovered: Bool,
        zones: DiagramZones
    ) {
        self.edge = edge
        self.action = action
        self.stripAction = stripAction
        self.dimmed = dimmed
        self.inherited = inherited
        self.note = note
        self.hovered = hovered
        self.zones = zones
    }

    /// The edge as the Edges and Corners & Taps tabs show it: the chosen action, grey when it is inherited, off or
    /// waiting for Accessibility.
    init(item: DiagramEdgeItem, hovered: Bool, zones: DiagramZones) {
        self.init(
            edge: item.edge,
            action: item.action,
            stripAction: item.stripAction,
            dimmed: item.isInherited || item.action == .off || item.note == .needsAccessibility,
            inherited: item.isInherited,
            note: item.note,
            hovered: hovered,
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

    private var color: Color {
        TrackpadDiagram.color(for: stripAction)
    }

    /// The zone's tint; stronger under the pointer.
    private var fill: Color {
        color.opacity(hovered ? 0.32 : 0.2)
    }

    /// The zone between its corners. A side zone with Bottom Quarter Only is filled only in its active lower part;
    /// above it the zone is faint with a dashed outline.
    @ViewBuilder
    private var band: some View {
        switch edge {
        case .top, .bottom:
            Rectangle()
                .fill(fill)
                .overlay {
                    stripLine(width: zones.endStripLength, height: DiagramZones.stripThickness)
                }
                .frame(width: zones.endLength, height: zones.endThickness)
                .contentShape(.rect)
        case .left, .right:
            VStack(spacing: 0) {
                Rectangle()
                    .fill(color.opacity(0.05))
                    .overlay {
                        Rectangle()
                            .strokeBorder(color.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    .frame(height: zones.inactiveSideLength)
                    .opacity(zones.inactiveSideLength > 0 ? 1 : 0)
                Rectangle()
                    .fill(fill)
                    .overlay {
                        stripLine(width: DiagramZones.stripThickness, height: zones.sideStripLength)
                    }
                    .frame(height: zones.activeSideLength)
            }
            .frame(width: zones.sideThickness, height: zones.sideLength)
            .contentShape(.rect)
        }
    }

    private func stripLine(width: CGFloat, height: CGFloat) -> some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: height)
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
