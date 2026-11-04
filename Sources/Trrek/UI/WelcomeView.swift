import SwiftUI
import TrrekAppCore

/// The welcome window's content: the trackpad diagram, a card per edge, Accessibility status and the way on.
struct WelcomeView: View {
    let model: WelcomeModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 16)
            HStack(alignment: .center, spacing: 16) {
                TrackpadDiagram(
                    settings: model.settings,
                    backlightAvailable: model.backlightAvailable,
                    accessibilityGranted: model.accessibilityGranted,
                    interactive: false
                )
                GlassEffectContainer(spacing: 8) {
                    VStack(spacing: 8) {
                        ForEach(model.cards, id: \.title) { card in
                            EdgeCard(card: card)
                        }
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
        .padding(.horizontal, 20)
        .padding(.top, 30)
        .padding(.bottom, 20)
        .frame(width: WelcomeWindowController.contentSize.width, height: WelcomeWindowController.contentSize.height)
        .containerBackground(.regularMaterial, for: .window)
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

/// A glass card with an edge's symbol, title and a line on how to use it.
private struct EdgeCard: View {
    let card: WelcomeCard

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: SettingsLabels.symbol(for: card.action) ?? "nosign")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(card.needsAccessibility ? .secondary : TrackpadDiagram.color(for: card.action))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(card.title)
                    .font(.subheadline.weight(.semibold))
                Text(card.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 44)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
