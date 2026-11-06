import Foundation

/// Why the update feed could not be used.
public enum ReleaseFeedError: Error, Equatable, Sendable {
    /// The answer is not JSON or not a release.
    case malformed
    /// The release has no tag, or its tag is not a version.
    case missingTag
    /// The release has no `trrek-vX.Y.Z.dmg` asset.
    case missingDiskImage
    /// The latest release is a draft or a prerelease.
    case notPublished
    /// The server answered with an HTTP status other than 200.
    case httpStatus(Int)
    /// The disk image or the release page is not where trrek's releases are published.
    case unexpectedLink

    /// The explanation shown in the "Couldn't check for updates" alert.
    public var message: String {
        switch self {
        case .malformed:
            String(localized: "The update information could not be read.", bundle: .main)
        case .missingTag, .missingDiskImage, .notPublished:
            String(localized: "The latest release could not be found.", bundle: .main)
        case let .httpStatus(status):
            String(localized: "The server answered with status \(status).", bundle: .main)
        case .unexpectedLink:
            String(localized: "The update information points to an unexpected address.", bundle: .main)
        }
    }
}

/// The parts of a published release the update check uses.
public struct ReleaseInfo: Codable, Equatable, Sendable {
    public let version: SemanticVersion
    /// The release page, opened when the download fails.
    public let pageURL: URL
    /// The disk image to download.
    public let diskImageURL: URL
    /// The release notes as published (Markdown list items).
    public let notes: String

    public init(version: SemanticVersion, pageURL: URL, diskImageURL: URL, notes: String) {
        self.version = version
        self.pageURL = pageURL
        self.diskImageURL = diskImageURL
        self.notes = notes
    }

    /// The disk image's file name for `version`: `trrek-vX.Y.Z.dmg`.
    public static func diskImageName(for version: SemanticVersion) -> String {
        "trrek-v\(version).dmg"
    }

    public var diskImageName: String {
        Self.diskImageName(for: version)
    }

    // MARK: - Trusted links

    /// The public releases repository on github.com.
    public static let repositoryPath = "/burakseyitkara1/trrek-releases"

    /// The only disk image address accepted for `version`: the release asset of tag `vX.Y.Z` (the server then
    /// redirects to its download host).
    public static func expectedDiskImageURL(for version: SemanticVersion) -> URL {
        let path = "\(repositoryPath)/releases/download/v\(version)/\(diskImageName(for: version))"
        return URL(string: "https://github.com" + path)!
    }

    /// Whether `url` is a page of the releases repository's releases: https on github.com at or under
    /// `/burakseyitkara1/trrek-releases/releases`, without credentials, port, query, fragment or `..`.
    public static func isReleasePage(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        let releases = repositoryPath + "/releases"
        let path = parts.path
        return parts.scheme == "https" && parts.host == "github.com"
            && parts.user == nil && parts.password == nil && parts.port == nil
            && parts.query == nil && parts.fragment == nil
            && (path == releases || path.hasPrefix(releases + "/"))
            && !path.split(separator: "/").contains("..")
    }

    /// Whether both links are the ones trrek's releases use; checked when the feed is read and when a stored
    /// update is read back.
    public var hasExpectedLinks: Bool {
        diskImageURL.absoluteString == Self.expectedDiskImageURL(for: version).absoluteString
            && Self.isReleasePage(pageURL)
    }

    /// Reads the answer of the releases API's `releases/latest` endpoint. Only the links `hasExpectedLinks` names
    /// are accepted.
    public static func decode(_ data: Data) throws(ReleaseFeedError) -> ReleaseInfo {
        let release: FeedRelease
        do {
            release = try JSONDecoder().decode(FeedRelease.self, from: data)
        } catch {
            throw .malformed
        }
        guard let tag = release.tagName, let version = SemanticVersion(tag) else { throw .missingTag }
        guard release.draft != true, release.prerelease != true else { throw .notPublished }
        let name = diskImageName(for: version)
        guard let asset = release.assets?.first(where: { $0.name == name }) else { throw .missingDiskImage }
        guard let page = release.htmlURL.flatMap(URL.init(string:)),
              let link = asset.browserDownloadURL.flatMap(URL.init(string:))
        else { throw .unexpectedLink }
        let info = ReleaseInfo(version: version, pageURL: page, diskImageURL: link, notes: release.body ?? "")
        guard info.hasExpectedLinks else { throw .unexpectedLink }
        return info
    }

    // MARK: - Notes

    /// The notes for an alert: line ends (also `\r\n` from notes edited on the web) made `\n`, list markers as
    /// bullets, code marks removed, cut at a line or word end to at most `limit` characters with an ellipsis.
    public static func excerpt(of notes: String, limit: Int = 600) -> String {
        let split = notes.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let lines = split.map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let text = trimmed.replacingOccurrences(of: "`", with: "")
            if text.hasPrefix("- ") || text.hasPrefix("* ") {
                return "• " + text.dropFirst(2)
            }
            return text
        }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > limit else { return text }
        let head = text.prefix(limit)
        // The last full line when it keeps at least half of the limit, else the last full word.
        var cut = head.lastIndex { $0 == " " || $0.isNewline } ?? head.endIndex
        let lineEnd = head.lastIndex(where: \.isNewline)
        if let lineEnd, head.distance(from: head.startIndex, to: lineEnd) >= limit / 2 {
            cut = lineEnd
        }
        return head[..<cut].trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

/// The fields read from a release; each optional, so a missing one is reported as what it means.
private struct FeedRelease: Decodable {
    let tagName: String?
    let htmlURL: String?
    let body: String?
    let draft: Bool?
    let prerelease: Bool?
    let assets: [FeedAsset]?

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body, draft, prerelease, assets
    }
}

private struct FeedAsset: Decodable {
    let name: String?
    let browserDownloadURL: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
