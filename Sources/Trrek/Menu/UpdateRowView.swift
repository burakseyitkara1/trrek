import AppKit
import TrrekAppCore

/// The update row at the top of the menu, as the menu item's view so a click starts the update without closing the
/// menu, and the row then shows the download's progress in place.
///
/// The row keeps one height in every state (the progress bar sits after the title), so the open menu never changes
/// its layout; its width fits the longest title any state can show. It draws the selection highlight itself, since
/// a menu item with a view draws nothing of its own; arrow keys reach it and Return sends the item's action.
@MainActor
final class UpdateRowView: NSView {
    static let height: CGFloat = 24
    private static let barWidth: CGFloat = 72
    private static let leading: CGFloat = 14
    private static let iconSize: CGFloat = 16
    private static let spacing: CGFloat = 6
    private static let trailing: CGFloat = 14

    var state: UpdateRowState {
        didSet {
            guard state != oldValue else { return }
            apply()
        }
    }

    /// Called when the row is clicked while it is clickable.
    var onClick: (() -> Void)?

    let label = NSTextField(labelWithString: "")
    let bar = NSProgressIndicator()
    private let icon = NSImageView()

    init(state: UpdateRowState) {
        self.state = state
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width(for: state.version), height: Self.height))
        autoresizingMask = [.width]
        icon.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
        icon.imageScaling = .scaleProportionallyDown
        label.font = Self.font
        label.lineBreakMode = .byTruncatingTail
        bar.style = .bar
        bar.controlSize = .small
        bar.minValue = 0
        bar.maxValue = 1
        bar.usesThreadedAnimation = true
        for view in [icon, label, bar] as [NSView] {
            addSubview(view)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        apply()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("unavailable")
    }

    private static var font: NSFont {
        NSFont.systemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize, weight: .semibold)
    }

    /// Wide enough for every title the row can show for `version`, the icon and the progress bar.
    static func width(for version: SemanticVersion) -> CGFloat {
        let states: [UpdateRowState] = [
            .available(version), .downloading(version, progress: nil), .installing(version), .failed(version),
            .browser(version), .relaunch(version)
        ]
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let widest = states.map { ($0.title as NSString).size(withAttributes: attributes).width }.max() ?? 0
        return ceil(leading + iconSize + spacing + widest + spacing + barWidth + trailing)
    }

    /// Whether the row shows as selected: the menu highlights it (pointer or arrow keys) and a click would act.
    var isHighlighted: Bool {
        Self.showsHighlight(itemHighlighted: enclosingMenuItem?.isHighlighted ?? false, clickable: state.isClickable)
    }

    /// The selection is drawn only for a highlighted row that a click would act on.
    static func showsHighlight(itemHighlighted: Bool, clickable: Bool) -> Bool {
        itemHighlighted && clickable
    }

    private func apply() {
        label.stringValue = state.title
        // The row stays short; why it failed is in its tooltip and read out with its title.
        let reason = state.failureReason
        setAccessibilityLabel(reason.map { "\(state.title). \($0)" } ?? state.title)
        toolTip = reason
        setAccessibilityEnabled(state.isClickable)
        switch state {
        case let .downloading(_, progress):
            bar.isHidden = false
            bar.isIndeterminate = progress == nil
            bar.doubleValue = progress ?? 0
            if progress == nil {
                bar.startAnimation(nil)
            } else {
                bar.stopAnimation(nil)
            }
            setAccessibilityValue(progress?.formatted(.percent.precision(.fractionLength(0))))
        case .installing:
            bar.isHidden = false
            bar.isIndeterminate = true
            bar.startAnimation(nil)
            setAccessibilityValue(nil)
        case .available, .failed, .browser, .relaunch:
            bar.stopAnimation(nil)
            bar.isHidden = true
            setAccessibilityValue(nil)
        }
        enclosingMenuItem?.isEnabled = state.isClickable
        // Not drawn, but used by type-select and as the accessibility fallback.
        enclosingMenuItem?.title = state.title
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let height = bounds.height
        icon.frame = NSRect(
            x: Self.leading,
            y: (height - Self.iconSize) / 2,
            width: Self.iconSize,
            height: Self.iconSize
        )
        let barX = bounds.width - Self.trailing - Self.barWidth
        bar.frame = NSRect(x: barX, y: (height - 12) / 2, width: Self.barWidth, height: 12)
        let labelX = icon.frame.maxX + Self.spacing
        let labelHeight = label.intrinsicContentSize.height
        let labelEnd = bar.isHidden ? bounds.width - Self.trailing : barX - Self.spacing
        label.frame = NSRect(x: labelX, y: (height - labelHeight) / 2, width: labelEnd - labelX, height: labelHeight)
    }

    override func viewWillDraw() {
        super.viewWillDraw()
        let color: NSColor = isHighlighted ? .selectedMenuItemTextColor : .labelColor
        label.textColor = color
        icon.contentTintColor = isHighlighted ? .selectedMenuItemTextColor : .controlAccentColor
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isHighlighted else { return }
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 5, yRadius: 5).fill()
    }

    /// Acts on the click itself and leaves the menu open, so the progress shows in place.
    override func mouseUp(with _: NSEvent) {
        click()
    }

    override func accessibilityPerformPress() -> Bool {
        guard state.isClickable else { return false }
        click()
        return true
    }

    func click() {
        guard state.isClickable else { return }
        onClick?()
    }
}
