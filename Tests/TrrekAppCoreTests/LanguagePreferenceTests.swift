import Foundation
import Testing
import TrrekAppCore

@Test func storedValuePerLanguage() {
    #expect(LanguagePreference.storedValue(for: .system) == nil)
    #expect(LanguagePreference.storedValue(for: .english) == ["en"])
    #expect(LanguagePreference.storedValue(for: .turkish) == ["tr"])
}

@Test func changeWritesOrRemovesOnlyWhenNeeded() {
    #expect(LanguagePreference.change(from: nil, to: .system) == .none)
    #expect(LanguagePreference.change(from: nil, to: .turkish) == .set(["tr"]))
    #expect(LanguagePreference.change(from: nil, to: .english) == .set(["en"]))
    #expect(LanguagePreference.change(from: ["tr"], to: .turkish) == .none)
    #expect(LanguagePreference.change(from: ["tr"], to: .english) == .set(["en"]))
    #expect(LanguagePreference.change(from: ["tr"], to: .system) == .remove)
    #expect(LanguagePreference.change(from: ["en"], to: .system) == .remove)
    // Values trrek did not write are replaced, or removed for the system language.
    #expect(LanguagePreference.change(from: ["tr", "en"], to: .turkish) == .set(["tr"]))
    #expect(LanguagePreference.change(from: "tr", to: .turkish) == .set(["tr"]))
    #expect(LanguagePreference.change(from: [String](), to: .system) == .remove)
    // The same language with a region, as the system may write it, is left alone.
    #expect(LanguagePreference.change(from: ["tr-TR"], to: .turkish) == .none)
    #expect(LanguagePreference.change(from: ["en-GB"], to: .english) == .none)
    #expect(LanguagePreference.change(from: ["tr-TR"], to: .english) == .set(["en"]))
}

@Test func languageNamedByStoredValue() {
    #expect(LanguagePreference.language(namedBy: nil) == nil)
    #expect(LanguagePreference.language(namedBy: [String]()) == nil)
    #expect(LanguagePreference.language(namedBy: "tr") == nil)
    #expect(LanguagePreference.language(namedBy: ["de"]) == nil)
    #expect(LanguagePreference.language(namedBy: ["tr"]) == .turkish)
    #expect(LanguagePreference.language(namedBy: ["tr-TR"]) == .turkish)
    #expect(LanguagePreference.language(namedBy: ["en-GB", "tr"]) == .english)
}

/// The per-app language chosen in System Settings is written to the same key; the setting adopts it at launch.
@Test func settingAdoptsALanguageChosenElsewhere() {
    #expect(LanguagePreference.adoptedLanguage(fromStored: ["tr"], setting: .system) == .turkish)
    #expect(LanguagePreference.adoptedLanguage(fromStored: ["tr-TR"], setting: .system) == .turkish)
    #expect(LanguagePreference.adoptedLanguage(fromStored: ["en"], setting: .system) == .english)
    #expect(LanguagePreference.adoptedLanguage(fromStored: ["en"], setting: .turkish) == .english)
    // Nothing to adopt: the same language, no preference, or a language trrek does not have.
    #expect(LanguagePreference.adoptedLanguage(fromStored: ["tr-TR"], setting: .turkish) == nil)
    #expect(LanguagePreference.adoptedLanguage(fromStored: nil, setting: .system) == nil)
    #expect(LanguagePreference.adoptedLanguage(fromStored: nil, setting: .turkish) == nil)
    #expect(LanguagePreference.adoptedLanguage(fromStored: ["de"], setting: .system) == nil)
}

@Test func adoptingThenApplyingLeavesTheSystemChoiceInPlace() {
    for stored in [["tr"], ["tr-TR"], ["en"], ["en-US"]] {
        let adopted = LanguagePreference.adoptedLanguage(fromStored: stored, setting: .system)
        #expect(adopted != nil)
        if let adopted {
            #expect(LanguagePreference.change(from: stored, to: adopted) == .none)
        }
    }
}

@Test func localizationPerLanguage() {
    let available = ["en", "tr"]
    #expect(LanguagePreference.localization(for: .english, available: available, systemLanguages: ["tr-TR"]) == "en")
    #expect(LanguagePreference.localization(for: .turkish, available: available, systemLanguages: ["en-US"]) == "tr")
    #expect(LanguagePreference
        .localization(for: .system, available: available, systemLanguages: ["tr-TR", "en"]) == "tr")
    #expect(LanguagePreference.localization(for: .system, available: available, systemLanguages: ["en-GB"]) == "en")
    #expect(LanguagePreference
        .localization(for: .system, available: available, systemLanguages: ["de-DE", "tr"]) == "tr")
    #expect(LanguagePreference.localization(for: .system, available: available, systemLanguages: []) == "en")
    #expect(LanguagePreference.localization(for: .system, available: [], systemLanguages: ["tr"]) == "en")
}

@Test func storedValuesRoundTripThroughChange() {
    for language in AppLanguage.allCases {
        #expect(LanguagePreference.change(from: LanguagePreference.storedValue(for: language), to: language) == .none)
    }
}

@Test func languageTitlesNameEachLanguageInItself() {
    #expect(AppLanguage.allCases.map(\.title) == ["System", "English", "Türkçe"])
}

/// Uses its own defaults suite, wiped before and after.
@Suite(.serialized)
struct LanguagePreferenceStoreTests {
    private static let suiteName = "trrek.tests.language"

    private static func fresh() throws -> (LanguagePreferenceStore, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (LanguagePreferenceStore(defaults: defaults, domain: suiteName), defaults)
    }

    @Test func applyWritesAndRemovesTheKey() throws {
        let (store, defaults) = try Self.fresh()
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }

        #expect(store.stored == nil)
        #expect(!store.apply(.system))

        #expect(store.apply(.turkish))
        #expect(store.stored as? [String] == ["tr"])
        #expect(!store.apply(.turkish))

        #expect(store.apply(.english))
        #expect(store.stored as? [String] == ["en"])

        #expect(store.apply(.system))
        #expect(store.stored == nil)
        #expect(defaults.persistentDomain(forName: Self.suiteName)?[LanguagePreference.key] == nil)
    }

    @Test func storedIgnoresOtherDomains() throws {
        let (store, defaults) = try Self.fresh()
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }
        // The global domain always has AppleLanguages; only trrek's own domain counts.
        #expect(defaults.object(forKey: LanguagePreference.key) != nil)
        #expect(store.stored == nil)
    }
}
