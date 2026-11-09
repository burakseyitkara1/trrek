import Foundation
import Testing

/// Reads the source for the localization keys it uses; see `LocalizationTests` for what it finds and its limits.
enum LocalizationScan {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    /// Source folders whose text reaches the interface.
    static let sourceFolders = ["Sources/Trrek", "Sources/TrrekAppCore"]

    // MARK: - Format specifiers

    /// The argument types of a format string's specifiers in argument order ("@", "lld"); `%%` is not one.
    static func specifiers(in format: String) -> [String] {
        let pattern = #"%(?:(\d+)\$)?[-+ 0#]*\d*(?:\.\d+)?(hh|h|ll|l|q|z|t|j)?([@dDiuUxXoOfeEgGcCsSp%])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let text = format as NSString
        var positional: [(Int, String)] = []
        for (index, match) in regex.matches(in: format, range: NSRange(location: 0, length: text.length)).enumerated() {
            let conversion = text.substring(with: match.range(at: 3))
            guard conversion != "%" else { continue }
            let length = match.range(at: 2).location == NSNotFound ? "" : text.substring(with: match.range(at: 2))
            let position = match.range(at: 1).location == NSNotFound
                ? index + 1
                : Int(text.substring(with: match.range(at: 1))) ?? index + 1
            positional.append((position, length + conversion))
        }
        return positional.sorted { $0.0 < $1.0 }.map(\.1)
    }

    // MARK: - Source scan

    struct Use {
        let file: String
        /// The literal as written, with `\u{…}` escapes resolved and interpolations kept as `\(…)`.
        let text: String
    }

    static func sourceFiles() throws -> [URL] {
        var files: [URL] = []
        for folder in sourceFolders {
            let url = root.appendingPathComponent(folder)
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
            while let file = enumerator?.nextObject() as? URL {
                if file.pathExtension == "swift" {
                    files.append(file)
                }
            }
        }
        #expect(!files.isEmpty)
        return files.sorted { $0.path < $1.path }
    }

    static func sourceKeys() throws -> [Use] {
        var uses: [Use] = []
        for file in try sourceFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            // An empty match is the opening of a multiline literal, read by `multilineLocalized`.
            for range in localizedLiteralRanges(in: text) where !range.isEmpty {
                uses.append(Use(file: file.lastPathComponent, text: unescape(String(text[range]))))
            }
            uses += multilineLocalized(in: text).map { Use(file: file.lastPathComponent, text: $0) }
        }
        return uses
    }

    /// One string literal's body: anything but a quote, backslash or newline, or an escape. An interpolation may hold
    /// one level of parentheses.
    static let literalBody = #"((?:[^"\\\n]|\\\((?:[^()]|\([^()]*\))*\)|\\.)*)"#

    /// The ranges of the literal bodies at the lookups listed in the type's documentation.
    static func localizedLiteralRanges(in text: String) -> [Range<String.Index>] {
        let views = "Text|Button|Toggle|Picker|Section|Label|LabeledContent|Tab|Menu|Link"
        let modifiers = "alert|help|accessibilityLabel|accessibilityHint|navigationTitle|confirmationDialog"
        let pattern = #"(?:String\(\s*localized:\s*|\b(?:"# + views + #")\(\s*|\.(?:"# + modifiers + #")\(\s*)""#
            + literalBody + "\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text)
        }
    }

    /// `String(localized: """ … """)` keys: the lines joined, with line continuations removed.
    static func multilineLocalized(in text: String) -> [String] {
        let pattern = #"String\(\s*localized:\s*"""\n(.*?)\n\s*""""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else {
            return []
        }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            let lines = text[range].split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            return lines.map { $0.hasSuffix("\\") ? String($0.dropLast()) : $0 + "\n" }.joined()
                .trimmingCharacters(in: .newlines)
        }
    }

    /// Every single-line string literal with its body's range.
    static func literals(in text: String) -> [(Range<String.Index>, String)] {
        guard let regex = try? NSRegularExpression(pattern: "\"" + literalBody + "\"") else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return (range, unescape(String(text[range])))
        }
    }

    static func line(containing index: String.Index, in text: String) -> Substring {
        let start = text[..<index].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let end = text[index...].firstIndex(of: "\n") ?? text.endIndex
        return text[start ..< end]
    }

    /// Resolves `\u{…}`, `\"`, `\\`, `\n` and `\t`; interpolations stay.
    static func unescape(_ literal: String) -> String {
        var result = ""
        var characters = literal[...]
        while let character = characters.popFirst() {
            guard character == "\\", let next = characters.first else {
                result.append(character)
                continue
            }
            switch next {
            case "u":
                characters.removeFirst()
                guard characters.first == "{", let close = characters.firstIndex(of: "}") else {
                    result += "\\u"
                    continue
                }
                let hex = characters[characters.index(after: characters.startIndex) ..< close]
                if let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) {
                    result.unicodeScalars.append(scalar)
                }
                characters = characters[characters.index(after: close)...]
            case "\"", "\\":
                characters.removeFirst()
                result.append(next)
            case "n":
                characters.removeFirst()
                result.append("\n")
            case "t":
                characters.removeFirst()
                result.append("\t")
            default:
                result.append(character)
            }
        }
        return result
    }

    /// Whether `key` is the key `use` produces: each `\(…)` in `use` matches one format specifier of `key`, `%` in
    /// the literal text appears as `%%` in `key`, and everything else must be the same.
    static func matches(key: String, use: String) -> Bool {
        let specifier = #"%(?:\d+\$)?[-+ 0#]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?[@dDiuUxXoOfeEgGcCsSp]"#
        var pattern = "^"
        var rest = use[...]
        while let start = rest.range(of: "\\(") {
            pattern += NSRegularExpression.escapedPattern(for: String(rest[..<start.lowerBound]))
                .replacingOccurrences(of: "%", with: "%%")
            var depth = 1
            var index = start.upperBound
            while index < rest.endIndex, depth > 0 {
                if rest[index] == "(" {
                    depth += 1
                }
                if rest[index] == ")" {
                    depth -= 1
                }
                index = rest.index(after: index)
            }
            pattern += specifier
            rest = rest[index...]
        }
        pattern += NSRegularExpression.escapedPattern(for: String(rest)).replacingOccurrences(of: "%", with: "%%")
        pattern += "$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)) != nil
    }
}
