import Foundation
import Testing

/// Checks the app's `.strings` files against each other and against the source.
///
/// The source scan finds keys written as string literals in the places that are looked up: `String(localized:)`,
/// SwiftUI views and modifiers that take a `LocalizedStringKey` (`Text`, `Button`, `Toggle`, `Picker`, `Section`,
/// `Label`, `LabeledContent`, `Tab`, `.alert`, `.help`, `.accessibilityLabel` …) and the Edges tab's `edgePicker`.
/// An interpolation (`\(…)`) matches any format specifier in the key. Its limits: a string built elsewhere and passed
/// as a `String` is shown verbatim by SwiftUI and is not seen here, and keys looked up dynamically (`dynamicKeys`) are
/// listed by hand. `unlocalizedProseIsAllowed` catches the first kind for literals of two or more words; a one-word
/// literal passed as a `String` is not caught.
struct LocalizationTests {
    private static let resources = LocalizationScan.root.appendingPathComponent("Sources/Trrek/Resources")
    private static let tables = ["Localizable", "InfoPlist"]
    private static let languages = ["en", "tr"]

    /// Keys looked up with a key that is not a literal at the lookup: the overlay label the dispatcher passes.
    private static let dynamicKeys = ["No DDC"]

    /// Turkish entries that are the same as the English on purpose: names and key names macOS does not translate.
    private static let untranslated: Set = [
        "%@ — %@", "Mission Control", "Spotlight", "Shift", "Option"
    ]

    private static func table(_ name: String, _ language: String) throws -> [String: String] {
        let url = resources.appendingPathComponent("\(language).lproj/\(name).strings")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(plist as? [String: String])
    }

    private static func entryCount(_ name: String, _ language: String) throws -> Int {
        let url = resources.appendingPathComponent("\(language).lproj/\(name).strings")
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n").count { $0.hasPrefix("\"") }
    }

    @Test func tablesHaveTheSameKeysInEveryLanguage() throws {
        for name in Self.tables {
            let english = try Self.table(name, "en")
            #expect(!english.isEmpty)
            for language in Self.languages {
                let table = try Self.table(name, language)
                #expect(Set(table.keys) == Set(english.keys), "\(language).lproj/\(name).strings")
                let extra = Set(table.keys).subtracting(english.keys).sorted()
                let missing = Set(english.keys).subtracting(table.keys).sorted()
                #expect(extra.isEmpty && missing.isEmpty, "\(language) \(name): extra \(extra), missing \(missing)")
            }
        }
    }

    @Test func tablesHaveNoDuplicateKeys() throws {
        for name in Self.tables {
            for language in Self.languages {
                #expect(try Self.entryCount(name, language) == Self.table(name, language).count, "\(language) \(name)")
            }
        }
    }

    /// The Info.plist template's values by key.
    private static func infoPlist() throws -> [String: Any] {
        let url = LocalizationScan.root.appendingPathComponent("Resources/Info.plist.in")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try #require(plist as? [String: Any])
    }

    /// Every English value is its key, except usage descriptions in `InfoPlist.strings`: the system looks those up by
    /// their Info.plist key, and their English value must be the one in Info.plist.
    @Test func englishValuesAreTheirKeys() throws {
        let info = try Self.infoPlist()
        for name in Self.tables {
            for (key, value) in try Self.table(name, "en") {
                if name == "InfoPlist", key.hasSuffix("UsageDescription") {
                    #expect(value == info[key] as? String, "\(key)")
                } else {
                    #expect(key == value)
                }
            }
        }
        #expect(try Self.table("InfoPlist", "en")["NSDownloadsFolderUsageDescription"] != nil)
    }

    @Test func translationsKeepTheFormatSpecifiers() throws {
        for name in Self.tables {
            for (key, value) in try Self.table(name, "tr") {
                #expect(
                    LocalizationScan.specifiers(in: value) == LocalizationScan.specifiers(in: key),
                    "\(key) → \(value)"
                )
            }
        }
    }

    @Test func everyTurkishEntryIsTranslated() throws {
        for name in Self.tables {
            for (key, value) in try Self.table(name, "tr") where !Self.untranslated.contains(key) {
                #expect(!value.isEmpty && value != key, "\(key)")
            }
        }
    }

    @Test func specifierParsing() {
        #expect(LocalizationScan.specifiers(in: "Paused in %@") == ["@"])
        #expect(LocalizationScan.specifiers(in: "%lld%%") == ["lld"])
        #expect(LocalizationScan.specifiers(in: "%%%lld") == ["lld"])
        #expect(LocalizationScan.specifiers(in: "%2$@ then %1$lld") == ["lld", "@"])
        #expect(LocalizationScan.specifiers(in: "100%") == [])
    }

    @Test func everyKeyInTheSourceIsInTheEnglishTable() throws {
        let english = try Self.table("Localizable", "en")
        let uses = try LocalizationScan.sourceKeys()
        #expect(uses.count > 100)
        for use in uses {
            let found = english.keys.contains { LocalizationScan.matches(key: $0, use: use.text) }
            #expect(found, "\(use.file): \"\(use.text)\" has no entry in en.lproj/Localizable.strings")
        }
        for key in Self.dynamicKeys {
            #expect(english[key] != nil, "\(key)")
        }
    }

    @Test func everyEnglishKeyIsUsed() throws {
        let english = try Self.table("Localizable", "en")
        let uses = try LocalizationScan.sourceKeys()
        for key in english.keys where !Self.dynamicKeys.contains(key) {
            #expect(uses.contains { LocalizationScan.matches(key: key, use: $0.text) }, "\(key) is not used")
        }
    }

    /// Literals with two or more words must be looked up, apart from log messages, comments, shell scripts, literals
    /// that wrap a lookup and the non-interface text listed in `allowed`.
    @Test func unlocalizedProseIsAllowed() throws {
        let allowed: Set = [
            // A restart reason, only logged.
            "device change",
            // An encoding error's debug description.
            "settings did not encode as an object"
        ]
        let words = try NSRegularExpression(pattern: "[A-Za-z]{2,} [A-Za-z]{2,}")
        let logCall = try NSRegularExpression(pattern: #"Logger|\.(?:debug|info|notice|error|fault)\("#)
        var offenders: [String] = []
        for file in try LocalizationScan.sourceFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            let localized = Set(LocalizationScan.localizedLiteralRanges(in: text).map(\.lowerBound))
            for (range, literal) in LocalizationScan.literals(in: text) where !localized.contains(range.lowerBound) {
                let line = String(LocalizationScan.line(containing: range.lowerBound, in: text))
                let isComment = line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
                let isLog = logCall.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
                let isCode = literal.contains("$") || literal.contains("localized:")
                guard !isComment, !isLog, !isCode, !allowed.contains(literal) else { continue }
                if words.firstMatch(in: literal, range: NSRange(literal.startIndex..., in: literal)) != nil {
                    offenders.append("\(file.lastPathComponent): \"\(literal)\"")
                }
            }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }

    @Test func keyMatching() {
        #expect(LocalizationScan.matches(key: "Paused in %@", use: #"Paused in \(name)"#))
        #expect(LocalizationScan.matches(key: "%lld%%", use: #"\(percent)%"#))
        #expect(LocalizationScan.matches(key: "Left edge — %@", use: #"Left edge — \(f(x))"#))
        #expect(!LocalizationScan.matches(key: "Paused in %@", use: "Paused in"))
        #expect(!LocalizationScan.matches(key: "Volume", use: "Volume."))
    }
}
