import SwiftUI
import TrrekAppCore
import TrrekEngine

/// A glass trackpad silhouette with the four edge strips and the four corner badges.
///
/// The strips and badges show what each edge and corner actually does: without Accessibility, the actions that
/// need it show as off. When `interactive` and Accessibility is granted, a click on a badge moves that corner to
/// its next action and passes the updated settings to `onChange`.
struct TrackpadDiagram: View {
    static let size = CGSize(width: 270, height: 180)
    /// The height on the Edges tab, where four edge pickers share the window's 480 pt with the diagram.
    static let compactHeight: CGFloat = 150
    private static let cornerRadius: CGFloat = 12
    private static let stripThickness: CGFloat = 5
    private static let inset: CGFloat = 8

    let settings: AppSettings
    let backlightAvailable: Bool
    let accessibilityGranted: Bool
    let interactive: Bool
    var onChange: ((AppSettings) -> Void)?
    var height: CGFloat = TrackpadDiagram.size.height
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
                horizontalStrip(edges.top, at: .top)
                horizontalStrip(edges.bottom, at: .bottom)
                verticalStrip(edges.left, at: .leading)
                verticalStrip(edges.right, at: .trailing)
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
    }

    // MARK: - Edges

    private func horizontalStrip(_ action: EdgeAction, at edge: VerticalEdge) -> some View {
        VStack(spacing: 6) {
            if edge == .bottom {
                Spacer(minLength: 0)
                EdgeLabel(action: action)
            }
            Capsule()
                .fill(Self.color(for: action))
                .frame(width: Self.size.width * 0.5, height: Self.stripThickness)
            if edge == .top {
                EdgeLabel(action: action)
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 2)
    }

    private func verticalStrip(_ action: EdgeAction, at edge: HorizontalEdge) -> some View {
        HStack(spacing: 6) {
            if edge == .trailing {
                Spacer(minLength: 0)
                EdgeLabel(action: action)
            }
            Capsule()
                .fill(Self.color(for: action))
                .frame(width: Self.stripThickness, height: height * 0.45)
            if edge == .leading {
                EdgeLabel(action: action)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 2)
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
        let action = ConfigMapper.gated(settings[corner: corner], accessibilityTrusted: accessibilityGranted)
        let help = "\(SettingsLabels.title(for: corner)): \(SettingsLabels.title(for: action))"
        if interactive, accessibilityGranted {
            Button {
                var updated = settings
                updated[corner: corner] = SettingsLabels.next(after: action)
                onChange?(updated)
            } label: {
                CornerBadge(action: action, interactive: true)
            }
            .buttonStyle(.plain)
            .help(help)
            .accessibilityLabel(help)
        } else {
            CornerBadge(action: action, interactive: false)
                .accessibilityLabel(help)
        }
    }

    private static func alignment(of corner: Corner) -> Alignment {
        switch corner {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
    }
}

/// An edge's symbol and name, or "Off" in grey.
private struct EdgeLabel: View {
    let action: EdgeAction

    var body: some View {
        HStack(spacing: 3) {
            if let symbol = SettingsLabels.symbol(for: action) {
                Image(systemName: symbol)
            }
            Text(SettingsLabels.title(for: action))
        }
        .font(.caption)
        .foregroundStyle(action == .off ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        .lineLimit(1)
        .fixedSize()
    }
}

/// A small glass badge with the corner action's symbol, or "Off".
private struct CornerBadge: View {
    let action: CornerAction
    let interactive: Bool

    var body: some View {
        Group {
            if let symbol = SettingsLabels.symbol(for: action) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
            } else {
                Text(SettingsLabels.title(for: action))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 34, height: 24)
        .contentShape(.rect(cornerRadius: 12))
        .glassEffect(.regular.interactive(interactive), in: .rect(cornerRadius: 12))
    }
}
