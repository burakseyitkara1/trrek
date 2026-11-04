import SwiftUI
import TrrekAppCore

/// The welcome window's content: the trackpad diagram, a card per edge, Accessibility status and the way on.
struct WelcomeView: View {
    let model: WelcomeModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 16)
            HStack(alignment: .center, spacing: WelcomeLayout.columnSpacing) {
                TrackpadDiagram(
                    settings: model.settings,
                    backlightAvailable: model.backlightAvailable,
                    accessibilityGranted: model.accessibilityGranted,
                    interactive: false
                )
                // No glass container here: a container draws its members' glass itself, past their opacity, so the
                // cards could not fade in.
                VStack(spacing: 8) {
                    ForEach(Array(model.cards.enumerated()), id: \.element.title) { index, card in
                        EdgeCard(card: card)
                            .opacity(model.cardsVisible ? 1 : 0)
                            .offset(y: model.cardsVisible ? 0 : 10)
                            .animation(
                                .smooth.delay(Double(index) * WelcomeModel.cardDelay),
                                value: model.cardsVisible
                            )
                    }
                }
            }
            Spacer(minLength: 16)
            accessibilityRow
            Spacer(minLength: 16)
            HStack(spacing: 10) {
                Spacer()
                Button("Open Settings") { model.openSettings() }
                    .buttonStyle(.glass)
                Button("Done") { model.close() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(.horizontal, WelcomeLayout.horizontalPadding)
        .padding(.top, 30)
        .padding(.bottom, 20)
        .frame(width: WelcomeWindowController.contentSize.width, height: WelcomeWindowController.contentSize.height)
        .containerBackground(.regularMaterial, for: .window)
        .onAppear {
            // The first frame has the cards hidden; they come in once it is on screen.
            DispatchQueue.main.async { [weak model] in
                MainActor.assumeIsolated { model?.revealCards() }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("Welcome to trrek")
                .font(.largeTitle.weight(.bold))
            Text("Slide one finger along an edge of the trackpad.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var accessibilityRow: some View {
        HStack(spacing: 10) {
            if model.accessibilityGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Accessibility access granted")
                    .font(.callout.weight(.semibold))
                Spacer(minLength: 0)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Accessibility access needed")
                        .font(.callout.weight(.semibold))
                    Text(SettingsLabels.accessibilityNeeded)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button("Grant Accessibility Access") { model.grantAccessibility() }
                    .buttonStyle(.glass)
            }
        }
        .font(.title3)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 48)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}

/// The welcome window's horizontal geometry in points; a card's title and detail must fit `cardTextWidth` at
/// `minimumTextScale` (checked for every card in both languages by `WelcomeLayoutTests`).
@MainActor
enum WelcomeLayout {
    static let horizontalPadding: CGFloat = 20
    /// Between the diagram and the card column.
    static let columnSpacing: CGFloat = 16
    static let cardPadding: CGFloat = 10
    static let cardSymbolWidth: CGFloat = 22
    /// Between a card's symbol and its text.
    static let cardSpacing: CGFloat = 10
    /// The smallest scale a card line shrinks to before it is cut.
    static let minimumTextScale: CGFloat = 0.8

    /// The width a card's title and detail lines get.
    static var cardTextWidth: CGFloat {
        WelcomeWindowController.contentSize.width - 2 * horizontalPadding - TrackpadDiagram.size.width
            - columnSpacing - 2 * cardPadding - cardSymbolWidth - cardSpacing
    }
}

/// A glass card with an edge's symbol, title and a line on how to use it.
private struct EdgeCard: View {
    let card: WelcomeCard

    var body: some View {
        HStack(spacing: WelcomeLayout.cardSpacing) {
            Image(systemName: SettingsLabels.symbol(for: card.action) ?? "nosign")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(card.needsAccessibility ? .secondary : TrackpadDiagram.color(for: card.action))
                .frame(width: WelcomeLayout.cardSymbolWidth)
            VStack(alignment: .leading, spacing: 1) {
                Text(card.title)
                    .font(.subheadline.weight(.semibold))
                Text(card.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(WelcomeLayout.minimumTextScale)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, WelcomeLayout.cardPadding)
        .frame(maxWidth: .infinity, minHeight: 44)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
