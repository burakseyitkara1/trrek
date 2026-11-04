import Foundation
import TrrekEngine

/// Why a `.trrek` file could not be imported.
public enum SettingsDocumentError: Error, Equatable, Sendable {
    /// The data is not JSON, or not a trrek settings file (its `format` is missing or different).
    case notSettingsFile
    /// The file was written by a newer trrek whose format or settings schema this build cannot read.
    case newerFormat

    /// The explanation shown under the import alert's title.
    public var message: String {
        switch self {
        case .notSettingsFile:
            String(
                localized: "The file is not a trrek settings file, or it is damaged. Your settings were not changed.",
                bundle: .main
            )
        case .newerFormat:
            String(
                localized: """
                The file was exported by a newer version of trrek. Update trrek to import it. \
                Your settings were not changed.
                """,
                bundle: .main
            )
        }
    }
}

/// Settings exported to, and imported from, a `.trrek` file.
///
/// The file is indented JSON with sorted keys:
/// `{"appVersion": "…", "format": "trrek-settings", "formatVersion": 1, "settings": {…}}`. Launch at Login,
/// whether the welcome window was shown and the interface language belong to this Mac and its user, so they are not
/// exported and an import keeps their current values (`imported(_:into:)`). The `settings` object is read with the
/// forgiving decoder: a missing or
/// unreadable field (such as an action this build does not know) takes its default.
public enum SettingsDocument {
    public static let format = "trrek-settings"
    public static let formatVersion = 1
    public static let fileExtension = "trrek"
    /// The exported type declared in the app's Info.plist.
    public static let typeIdentifier = "com.burakseyitkara.trrek.settings"
    /// The name the export panel suggests, in the interface language.
    public static var defaultFileName: String {
        "\(String(localized: "trrek Settings", bundle: .main)).\(fileExtension)"
    }

    /// Fields that describe this Mac rather than how trrek behaves.
    static let localKeys: Set<String> = ["launchAtLogin", "welcomeShown", "language"]

    /// Larger files are refused without being read; an exported file is about 1 KB.
    public static let maximumFileSize = 1_000_000

    /// The file contents for `settings`. Throws when the settings cannot be encoded, so a failed export never
    /// writes an empty or partial file.
    public static func encode(_ settings: Settings) throws -> Data {
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings))
        guard let object = encoded as? [String: Any] else {
            throw EncodingError.invalidValue(
                settings,
                EncodingError.Context(codingPath: [], debugDescription: "settings did not encode as an object")
            )
        }
        let fields = object.filter { !localKeys.contains($0.key) }
        let document: [String: Any] = [
            "format": format,
            "formatVersion": formatVersion,
            "appVersion": TrrekVersion.string,
            "settings": fields
        ]
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try JSONSerialization.data(withJSONObject: document, options: options)
    }

    /// The contents of the file at `url`, refusing anything that is not a regular file or is larger than
    /// `maximumFileSize` as `SettingsDocumentError.notSettingsFile` before reading it. Reads synchronously; call it
    /// off the main actor. Other read failures are rethrown.
    public static func read(contentsOf url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, (values.fileSize ?? 0) <= maximumFileSize else {
            throw SettingsDocumentError.notSettingsFile
        }
        let data = try Data(contentsOf: url)
        // The file can grow between the size check and the read.
        guard data.count <= maximumFileSize else { throw SettingsDocumentError.notSettingsFile }
        return data
    }

    /// The settings in a file's contents. `launchAtLogin`, `welcomeShown` and `language` keep their defaults; apply the
    /// result with `imported(_:into:)`.
    public static func decode(_ data: Data) throws(SettingsDocumentError) -> Settings {
        let header: DocumentHeader
        do {
            header = try JSONDecoder().decode(DocumentHeader.self, from: data)
        } catch {
            throw .notSettingsFile
        }
        guard header.format == format, let version = header.formatVersion, version >= 1 else {
            throw .notSettingsFile
        }
        guard version <= formatVersion else { throw .newerFormat }
        // The forgiving decoder loads a newer settings schema as all defaults; an import refuses it instead.
        if let schema = header.settings?.schemaVersion, schema > Settings.currentSchemaVersion {
            throw .newerFormat
        }
        do {
            var settings = try JSONDecoder().decode(DocumentBody.self, from: data).settings
            let defaults = Settings()
            settings.launchAtLogin = defaults.launchAtLogin
            settings.welcomeShown = defaults.welcomeShown
            settings.language = defaults.language
            return settings
        } catch {
            throw .notSettingsFile
        }
    }

    /// `imported` with `current`'s Launch at Login, welcome state and language.
    public static func imported(_ imported: Settings, into current: Settings) -> Settings {
        var result = imported
        result.launchAtLogin = current.launchAtLogin
        result.welcomeShown = current.welcomeShown
        result.language = current.language
        return result
    }

    /// Whether `url` names a settings file, judged by its extension.
    public static func isSettingsFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == fileExtension
    }
}

/// The top-level fields of a settings file, each optional so a different document is told apart from a damaged one.
private struct DocumentHeader: Decodable {
    let format: String?
    let formatVersion: Int?
    let settings: DocumentSettingsHeader?
}

/// The settings schema version, `nil` when missing or unreadable.
private struct DocumentSettingsHeader: Decodable {
    let schemaVersion: Int?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try? container.decodeIfPresent(Int.self, forKey: .schemaVersion)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
    }
}

private struct DocumentBody: Decodable {
    let settings: Settings
}
