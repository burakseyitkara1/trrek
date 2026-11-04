import AppKit
import Foundation
import Testing
import TrrekAppCore

/// The settings window's tab bar is one segmented toolbar item whose segments all take the width of the widest tab
/// title. When it does not fit beside the window title, the system moves the whole bar into an overflow menu and
/// no tab is visible. Measured in the 640 pt window: the bar shows with a widest title of 109 pt and overflows at
/// 120 pt, so every title in every language must stay within 112 pt at the system font size.
@MainActor
struct SettingsTabBarLayoutTests {
    private static let widestTitle: CGFloat = 112

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

    private static func width(_ text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    @Test func everyTabTitleFitsTheTabBarInBothLanguages() throws {
        #expect(!Self.turkish.isEmpty)
        for tab in SettingsTab.allCases {
            // Tests have no translations, so `title` is the English text and also the key of the Turkish one.
            let english = tab.title
            let turkish = try #require(Self.turkish[english], "\(english)")
            for title in [english, turkish] {
                #expect(Self.width(title) <= Self.widestTitle, "\(title): \(Self.width(title)) pt")
            }
        }
    }
}
