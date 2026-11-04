import AppKit
import Foundation
import Testing
@testable import Trrek
import TrrekAppCore
import TrrekEngine

/// Every welcome card line, in English and Turkish, fits its card at the smallest scale it may shrink to, measured with
/// the fonts the card uses (`.subheadline` semibold for the title, `.caption` for the detail).
@MainActor
struct WelcomeLayoutTests {
    private static let turkish: [String: String] = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Trrek/Resources/tr.lproj/Localizable.strings")
        guard let data = try? Data(contentsOf: url),
              let table = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        else { return [:] }
        return table
    }()

    private static func width(_ text: String, _ font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Every card the window can show: each action on each edge, with and without Accessibility. Tests have no
    /// translations, so the cards come out in English.
    private static var englishCards: [WelcomeCard] {
        var cards: [WelcomeCard] = []
        for action in EdgeAction.allCases {
            var settings = AppSettings()
            for edge in Edge.allCases {
                settings[edge: edge] = action
            }
            for trusted in [true, false] {
                cards += WelcomeContent.cards(for: settings, backlightAvailable: true, accessibilityTrusted: trusted)
            }
        }
        return cards
    }

    /// The Turkish title: the edge's phrase with the action's Turkish name.
    private static func turkishTitle(of card: WelcomeCard) throws -> String {
        let phrase = switch card.edge {
        case .left: "Left edge — %@"
        case .right: "Right edge — %@"
        case .top: "Top edge — %@"
        case .bottom: "Bottom edge — %@"
        }
        let format = try #require(turkish[phrase])
        let action = try #require(turkish[SettingsLabels.title(for: card.action)])
        return String(format: format, action)
    }

    @Test func cardTextWidthMatchesTheWindow() {
        // 560 − 2×20 − 270 − 16 − 2×10 − 22 − 10
        #expect(WelcomeLayout.cardTextWidth == 182)
    }

    @Test func everyCardLineFitsInBothLanguages() throws {
        #expect(!Self.turkish.isEmpty)
        let caption = NSFont.preferredFont(forTextStyle: .caption1)
        let subheadline = NSFont.preferredFont(forTextStyle: .subheadline)
        let title = NSFont.systemFont(ofSize: subheadline.pointSize, weight: .semibold)
        let limit = WelcomeLayout.cardTextWidth / WelcomeLayout.minimumTextScale
        let cards = Self.englishCards
        #expect(cards.count == EdgeAction.allCases.count * 2 * 4)
        for card in cards {
            let lines = try [
                (card.title, title),
                (Self.turkishTitle(of: card), title),
                (card.detail, caption),
                (#require(Self.turkish[card.detail], "\(card.detail)"), caption)
            ]
            for (text, font) in lines {
                #expect(Self.width(text, font) <= limit, "\(text): \(Self.width(text, font)) pt > \(limit) pt")
            }
        }
    }
}
