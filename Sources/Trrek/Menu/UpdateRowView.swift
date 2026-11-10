import AppKit
import TrrekAppCore

/// The menu's update row (`MenuUpdateRowState`), as the menu item's view so a click checks or starts the update
/// without closing the menu, and the row then shows the check and the download in place.
///
/// The row keeps one height in every state (the spinner and the icon sit before the title, the progress bar after
/// it), so the open menu never changes its layout; its width fits the longest title any state can show. The title
/// lines up with the other items' titles and the icon sits in their checkmark column. It draws the selection
/// highlight itself, since a menu item with a view draws nothing of its own; arrow keys reach it and Return sends
/// the item's action.
@MainActor
final class UpdateRowView: NSView {
    static let height: CGFloat = 24
    static let barWidth: CGFloat = 72
    /// The label's x, so its text (inset 2 points in the label) starts where the other items' titles do.
    static let titleX: CGFloat = 28
    /// The centre of the other items' checkmark column.
    private static let iconCenterX: CGFloat = 18
    private static let iconSize: CGFloat = 14
    private static let spinnerSize: CGFloat = 16
    private static let spacing: CGFloat = 8
    private static let trailing: CGFloat = 14

    var state: MenuUpdateRowState {
        didSet {
            guard state != oldValue else { return }
            apply()
            announceChange(from: oldValue)
        }
    }

    /// Whether the spinner or the indeterminate bar animates; only while they show in an open menu.
    private(set) var isAnimating = false

    /// Called when the row is clicked while it is clickable.
    var onClick: (() -> Void)?

    let label = NSTextField(labelWithString: "")
    let bar = NSProgressIndicator()
    let spinner = NSProgressIndicator()
    let icon = NSImageView()

    init(state: MenuUpdateRowState, width: CGFloat) {
        self.state = state
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))
        autoresizingMask = [.width]
        icon.imageScaling = .scaleProportionallyDown
        label.lineBreakMode = .byTruncatingTail
        bar.style = .bar
        bar.controlSize = .small
        bar.minValue = 0
        bar.maxValue = 1
        bar.usesThreadedAnimation = true
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.usesThreadedAnimation = true
        for view in [icon, spinner, label, bar] as [NSView] {
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

    static func font(for state: MenuUpdateRowState) -> NSFont {
        font(isProminent: state.isProminent)
    }

    static func font(isProminent: Bool) -> NSFont {
        let size = NSFont.menuFont(ofSize: 0).pointSize
        return NSFont.systemFont(ofSize: size, weight: isProminent ? .semibold : .regular)
    }

    /// A title the row may show, for measuring: its text, whether it is semibold and whether the bar follows it.
    struct Title {
        var text: String
        var isProminent: Bool
        var showsProgressBar: Bool

        init(_ state: MenuUpdateRowState) {
            self.init(text: state.title, isProminent: state.isProminent, showsProgressBar: state.showsProgressBar)
        }

        init(text: String, isProminent: Bool, showsProgressBar: Bool) {
            self.text = text
            self.isProminent = isProminent
            self.showsProgressBar = showsProgressBar
        }
    }

    /// Wide enough for every title of `samples` (`MenuUpdateRowState.widthSamples`), with the progress bar after the
    /// titles that show it.
    static func width(for samples: [MenuUpdateRowState]) -> CGFloat {
        width(for: samples.map(Title.init))
    }

    /// Wide enough for every title, measured as the label draws it (with the text field cell's padding).
    static func width(for titles: [Title]) -> CGFloat {
        let measure = NSTextField(labelWithString: "")
        let widest = titles.map { title in
            measure.font = font(isProminent: title.isProminent)
            measure.stringValue = title.text
            let label = ceil(measure.cell?.cellSize.width ?? 0)
            return label + (title.showsProgressBar ? spacing + barWidth : 0)
        }.max() ?? 0
        return ceil(titleX + widest + trailing)
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
        label.font = Self.font(for: state)
        // The row stays short; why it failed is in its tooltip and read out with its title.
        setAccessibilityLabel(state.accessibilityLabel)
        toolTip = state.failureReason
        setAccessibilityEnabled(state.isClickable)
        let symbol: String? = switch state.icon {
        case .none, .spinner: nil
        case .checkmark: "checkmark.circle.fill"
        case .warning: "exclamationmark.circle.fill"
        case .update: "arrow.down.circle.fill"
        }
        icon.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        icon.isHidden = symbol == nil
        bar.isHidden = !state.showsProgressBar
        bar.isIndeterminate = state.progress == nil
        bar.doubleValue = state.progress ?? 0
        setAccessibilityValue(state.progress?.formatted(.percent.precision(.fractionLength(0))))
        updateAnimation()
        enclosingMenuItem?.isEnabled = state.isClickable
        // Not drawn, but used by type-select and as the accessibility fallback.
        enclosingMenuItem?.title = state.title
        needsLayout = true
        needsDisplay = true
    }

    /// The spinner and the indeterminate bar animate only while they show in an open menu.
    private func updateAnimation(menuOpen: Bool = true) {
        let visible = menuOpen && window != nil
        let spins = visible && state.icon == .spinner
        let fills = visible && state.showsProgressBar && state.progress == nil
        if spins {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
        if fills {
            bar.startAnimation(nil)
        } else {
            bar.stopAnimation(nil)
        }
        isAnimating = spins || fills
    }

    /// The menu closed: stops the animations at once, whether or not the menu keeps the view in its window.
    func menuDidClose() {
        updateAnimation(menuOpen: false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAnimation()
    }

    /// The row changes in place, so VoiceOver is told: the new title while it shows, and the outcome of a manual
    /// check as an announcement (also when the menu closed before it arrived).
    private func announceChange(from old: MenuUpdateRowState) {
        if old.title != state.title, window != nil {
            NSAccessibility.post(element: self, notification: .titleChanged)
        }
        if let announcement = state.announcement(after: old) {
            // A view outside a window reaches no one; the app then makes the announcement.
            let element: Any = window != nil ? self : NSApplication.shared
            NSAccessibility.post(element: element, notification: .announcementRequested, userInfo: [
                .announcement: announcement,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ])
        }
    }

    override func layout() {
        super.layout()
        let height = bounds.height
        let iconFrame = NSRect(
            x: Self.iconCenterX - Self.iconSize / 2,
            y: (height - Self.iconSize) / 2,
            width: Self.iconSize,
            height: Self.iconSize
        )
        icon.frame = iconFrame
        let inset = (Self.iconSize - Self.spinnerSize) / 2
        spinner.frame = iconFrame.insetBy(dx: inset, dy: inset)
        let barX = bounds.width - Self.trailing - Self.barWidth
        bar.frame = NSRect(x: barX, y: (height - 12) / 2, width: Self.barWidth, height: 12)
        let labelHeight = label.intrinsicContentSize.height
        let labelEnd = bar.isHidden ? bounds.width - Self.trailing : barX - Self.spacing
        label.frame = NSRect(
            x: Self.titleX,
            y: (height - labelHeight) / 2,
            width: labelEnd - Self.titleX,
            height: labelHeight
        )
    }

    override func viewWillDraw() {
        super.viewWillDraw()
        let highlighted = isHighlighted
        label.textColor = highlighted ? .selectedMenuItemTextColor : .labelColor
        let tint: NSColor = switch state.icon {
        case .checkmark: .systemGreen
        case .warning: .systemOrange
        case .none, .spinner, .update: .controlAccentColor
        }
        icon.contentTintColor = highlighted ? .selectedMenuItemTextColor : tint
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isHighlighted else { return }
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 5, yRadius: 5).fill()
    }

    /// Acts on the click itself and leaves the menu open, so the check and the progress show in place.
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
