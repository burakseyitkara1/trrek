import Foundation
import Testing
import TrrekAppCore
import TrrekEngine

/// The release feed fixture (a trimmed answer of the live `releases/latest` endpoint for v0.3.0) and small JSON
/// builders.
enum UpdateFixtures {
    static let latestRelease: Data = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/latest-release.json")
        return (try? Data(contentsOf: url)) ?? Data()
    }()

    static func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    static let releases = "https://github.com/burakseyitkara1/trrek/releases"

    /// A release with a disk image and a zip at the releases repository's addresses for `tag`, unless `download`
    /// gives another address for the disk image.
    static func release(
        tag: String = "v1.2.3",
        draft: Bool = false,
        prerelease: Bool = false,
        assets: [String]? = nil,
        page: String? = nil,
        download: String? = nil
    ) throws -> Data {
        let names = assets ?? ["trrek-\(tag).dmg", "trrek-\(tag).zip"]
        return try json([
            "tag_name": tag,
            "html_url": page ?? "\(releases)/tag/\(tag)",
            "body": "- One\n- Two\n",
            "draft": draft,
            "prerelease": prerelease,
            "assets": names.map { name in
                let standard = "\(releases)/download/\(tag)/\(name)"
                return ["name": name, "browser_download_url": name.hasSuffix(".dmg") ? download ?? standard : standard]
            }
        ])
    }
}

struct SemanticVersionTests {
    @Test func parsesWithAndWithoutPrefix() {
        #expect(SemanticVersion("0.3.0") == SemanticVersion(major: 0, minor: 3, patch: 0))
        #expect(SemanticVersion("v1.20.3") == SemanticVersion(major: 1, minor: 20, patch: 3))
        #expect(SemanticVersion("V2.0.0") == SemanticVersion(major: 2, minor: 0, patch: 0))
        #expect(SemanticVersion("v0.3.0")?.description == "0.3.0")
    }

    @Test func refusesGarbage() {
        let garbage = [
            "", "v", "1", "1.2", "1.2.3.4", "1..3", "a.b.c", "1.2.3-beta", " 1.2.3", "1.2.3 ", "+1.2.3", "1.-2.3",
            "vv1.2.3", "1.2.٣", "1234567890.0.0"
        ]
        for text in garbage {
            #expect(SemanticVersion(text) == nil, "\(text)")
        }
    }

    @Test func comparesComponentWise() throws {
        let ordered = try ["0.2.9", "0.3.0", "0.3.1", "0.4.0", "0.10.0", "1.0.0"].map {
            try #require(SemanticVersion($0))
        }
        for (lower, higher) in zip(ordered, ordered.dropFirst()) {
            #expect(lower < higher, "\(lower) < \(higher)")
            #expect(!(higher < lower))
        }
        #expect(SemanticVersion("v0.3.0") == SemanticVersion("0.3.0"))
    }

    @Test func runningVersionParses() {
        #expect(SemanticVersion(TrrekVersion.string) != nil)
    }

    @Test func codableAsText() throws {
        let version = try #require(SemanticVersion("1.2.3"))
        let data = try JSONEncoder().encode([version])
        #expect(String(data: data, encoding: .utf8) == #"["1.2.3"]"#)
        #expect(try JSONDecoder().decode([SemanticVersion].self, from: data) == [version])
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([SemanticVersion].self, from: Data(#"["one"]"#.utf8))
        }
    }
}

struct ReleaseInfoTests {
    @Test func decodesTheLiveFixture() throws {
        let release = try ReleaseInfo.decode(UpdateFixtures.latestRelease)
        #expect(release.version == SemanticVersion("0.3.0"))
        #expect(release.pageURL.absoluteString
            == "https://github.com/burakseyitkara1/trrek/releases/tag/v0.3.0")
        #expect(release.diskImageURL.absoluteString
            == "https://github.com/burakseyitkara1/trrek/releases/download/v0.3.0/trrek-v0.3.0.dmg")
        #expect(release.diskImageName == "trrek-v0.3.0.dmg")
        #expect(release.notes.hasPrefix("- Export Settings…"))
    }

    @Test func malformedAnswersAreRefused() throws {
        #expect(throws: ReleaseFeedError.malformed) { try ReleaseInfo.decode(Data("not json".utf8)) }
        #expect(throws: ReleaseFeedError.malformed) { try ReleaseInfo.decode(Data("[]".utf8)) }
        #expect(throws: ReleaseFeedError.malformed) { try ReleaseInfo.decode(Data(#"{"tag_name": 3}"#.utf8)) }
    }

    @Test func aMissingOrInvalidTagIsRefused() throws {
        let noTag = try UpdateFixtures.json(["html_url": UpdateFixtures.releases, "assets": []])
        #expect(throws: ReleaseFeedError.missingTag) { try ReleaseInfo.decode(noTag) }
        #expect(throws: ReleaseFeedError.missingTag) { try ReleaseInfo.decode(UpdateFixtures.release(tag: "latest")) }
    }

    @Test func aMissingDiskImageIsRefused() throws {
        #expect(throws: ReleaseFeedError.missingDiskImage) {
            try ReleaseInfo.decode(UpdateFixtures.release(assets: ["trrek-v1.2.3.zip"]))
        }
        // The image must be the one for the tag's version.
        #expect(throws: ReleaseFeedError.missingDiskImage) {
            try ReleaseInfo.decode(UpdateFixtures.release(assets: ["trrek-v1.2.2.dmg"]))
        }
    }

    /// A feed that names another server, another repository or another version's file is refused, whatever the
    /// asset is called.
    @Test func onlyTheReleasesRepositoryIsTrusted() throws {
        let releases = UpdateFixtures.releases
        let hostileDownloads = [
            "http://github.com/burakseyitkara1/trrek/releases/download/v1.2.3/trrek-v1.2.3.dmg",
            "https://example.com/burakseyitkara1/trrek/releases/download/v1.2.3/trrek-v1.2.3.dmg",
            "https://github.com.example.com/burakseyitkara1/trrek/releases/download/v1.2.3/trrek-v1.2.3.dmg",
            "https://evil@github.com/burakseyitkara1/trrek/releases/download/v1.2.3/trrek-v1.2.3.dmg",
            "https://github.com:8443/burakseyitkara1/trrek/releases/download/v1.2.3/trrek-v1.2.3.dmg",
            "https://github.com/someone/trrek/releases/download/v1.2.3/trrek-v1.2.3.dmg",
            // The releases-only repository earlier versions read is no longer trusted.
            "https://github.com/burakseyitkara1/trrek-releases/releases/download/v1.2.3/trrek-v1.2.3.dmg",
            "\(releases)/download/v1.2.2/trrek-v1.2.3.dmg",
            "\(releases)/download/v1.2.3/trrek-v1.2.2.dmg",
            "\(releases)/download/v1.2.3/trrek-v1.2.3.dmg?x=1",
            "\(releases)/download/v1.2.3/../v9.0.0/trrek-v1.2.3.dmg",
            "not a url"
        ]
        for link in hostileDownloads {
            #expect(throws: ReleaseFeedError.unexpectedLink, "\(link)") {
                try ReleaseInfo.decode(UpdateFixtures.release(download: link))
            }
        }
        let hostilePages = [
            "http://github.com/burakseyitkara1/trrek/releases/tag/v1.2.3",
            "https://example.com/burakseyitkara1/trrek/releases/tag/v1.2.3",
            "https://github.com/someone/trrek/releases/tag/v1.2.3",
            "https://github.com/burakseyitkara1/trrek-releases/releases/tag/v1.2.3",
            "https://github.com/burakseyitkara1/trrek/issues",
            "https://github.com/burakseyitkara1/trrek/releases/../../other",
            "https://github.com/burakseyitkara1/trrekx/releases",
            "\(releases)/tag/v1.2.3#top"
        ]
        for page in hostilePages {
            #expect(throws: ReleaseFeedError.unexpectedLink, "\(page)") {
                try ReleaseInfo.decode(UpdateFixtures.release(page: page))
            }
        }
        let release = try ReleaseInfo.decode(UpdateFixtures.release())
        #expect(release.hasExpectedLinks)
        #expect(release.diskImageURL.absoluteString == "\(releases)/download/v1.2.3/trrek-v1.2.3.dmg")
        #expect(try ReleaseInfo.isReleasePage(#require(URL(string: releases))))
    }

    @Test func draftsAndPrereleasesAreIgnored() throws {
        #expect(throws: ReleaseFeedError.notPublished) { try ReleaseInfo.decode(UpdateFixtures.release(draft: true)) }
        #expect(throws: ReleaseFeedError.notPublished) {
            try ReleaseInfo.decode(UpdateFixtures.release(prerelease: true))
        }
        #expect(try ReleaseInfo.decode(UpdateFixtures.release()).version == SemanticVersion("1.2.3"))
    }

    @Test func errorsHaveMessages() {
        let errors: [ReleaseFeedError] = [
            .malformed, .missingTag, .missingDiskImage, .notPublished, .httpStatus(403), .unexpectedLink, .tooLarge
        ]
        for error in errors {
            #expect(!error.message.isEmpty)
        }
        #expect(ReleaseFeedError.httpStatus(403).message.contains("403"))
    }

    @Test func excerptShowsBulletsWithoutCodeMarks() {
        let notes = "- Export to a `.trrek` file\n* Turkish\n\nPlain line  \n"
        #expect(ReleaseInfo.excerpt(of: notes) == "• Export to a .trrek file\n• Turkish\n\nPlain line")
        #expect(ReleaseInfo.excerpt(of: "  \n") == "")
        // Notes edited on the web end their lines with \r\n.
        #expect(ReleaseInfo.excerpt(of: "- a\r\n- `b`\r\n\r\nc\r\n") == "• a\n• b\n\nc")
    }

    @Test func excerptIsCutAtALineOrWordEnd() {
        let line = String(repeating: "word ", count: 30) // 150 characters
        let notes = (0 ..< 8).map { _ in "- " + line }.joined(separator: "\n")
        let excerpt = ReleaseInfo.excerpt(of: notes, limit: 600)
        #expect(excerpt.count <= 601)
        #expect(excerpt.hasSuffix("word…"))
        #expect(!excerpt.contains("\n…"))
        // Cut after the third full line: the fourth would pass the limit.
        #expect(excerpt.split(separator: "\n").count == 3)
        #expect(ReleaseInfo.excerpt(of: notes.replacingOccurrences(of: "\n", with: "\r\n"), limit: 600) == excerpt)

        let words = String(repeating: "abc ", count: 200)
        let cut = ReleaseInfo.excerpt(of: words, limit: 50)
        #expect(cut.count <= 51)
        #expect(cut.hasSuffix("abc…"))

        let fixture = ReleaseInfo.excerpt(of: (try? ReleaseInfo.decode(UpdateFixtures.latestRelease))?.notes ?? "")
        #expect(fixture.count <= 601)
        #expect(fixture.hasPrefix("• Export Settings…"))
    }
}

struct ReleaseNetworkTests {
    @Test func requestSendsOnlyAcceptAndUserAgent() {
        let request = ReleaseFeedClient.request()
        #expect(request.url == ReleaseFeedClient.latestReleaseURL)
        #expect(request.url?.absoluteString
            == "https://api.github.com/repos/burakseyitkara1/trrek/releases/latest")
        #expect(request.httpMethod == "GET")
        #expect(request.allHTTPHeaderFields == [
            "Accept": "application/vnd.github+json",
            "User-Agent": "trrek/\(TrrekVersion.string)"
        ])
        #expect(!request.httpShouldHandleCookies)
        #expect(request.timeoutInterval == 15)
    }

    @Test func sessionKeepsNothing() {
        let configuration = ReleaseFeedClient.configuration(resourceTimeout: 15)
        #expect(configuration.httpCookieStorage == nil)
        #expect(!configuration.httpShouldSetCookies)
        #expect(configuration.urlCache == nil)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(configuration.timeoutIntervalForRequest == 15)
        #expect(configuration.timeoutIntervalForResource == 15)

        let download = ReleaseFeedClient.configuration(
            requestTimeout: SessionFileDownloader.idleTimeout,
            resourceTimeout: SessionFileDownloader.resourceTimeout
        )
        #expect(download.timeoutIntervalForRequest == 60)
        #expect(download.timeoutIntervalForResource == 600)
        #expect(download.httpCookieStorage == nil)
    }
}

/// Answers with a fixed result and counts the calls.
actor FakeReleaseFeed: ReleaseFeed {
    var result: Result<Data, any Error>
    private(set) var calls = 0

    init(_ result: Result<Data, any Error>) {
        self.result = result
    }

    func set(_ result: Result<Data, any Error>) {
        self.result = result
    }

    func latestRelease() async throws -> Data {
        calls += 1
        return try result.get()
    }
}

/// "Downloads" by writing `contents` to a new temporary file, reporting half and then all of it.
struct FakeFileDownloader: FileDownloading {
    let contents: Data

    func download(from _: URL, progress: @escaping DownloadProgress) async throws -> URL {
        let size = Int64(contents.count)
        progress(size / 2, size)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try contents.write(to: file)
        progress(size, size)
        return file
    }
}

struct UpdateDownloaderTests {
    private static func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("trrek-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func downloadsUnderTheReleaseNameReplacingAnOldFile() async throws {
        let root = try Self.folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Caches/Updates")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let release = try ReleaseInfo.decode(UpdateFixtures.latestRelease)
        let destination = folder.appendingPathComponent("trrek-v0.3.0.dmg")
        try Data("old".utf8).write(to: destination)

        let downloader = UpdateDownloader(client: FakeFileDownloader(contents: Data("new".utf8)))
        let image = try await downloader.download(release, to: folder)
        let file = image.file

        #expect(file == destination)
        #expect(image.isQuarantined)
        #expect(try Data(contentsOf: file) == Data("new".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["trrek-v0.3.0.dmg"])
        let quarantine = try file.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties
        #expect(quarantine?["LSQuarantineAgentName"] as? String == "trrek")
    }

    @Test func aFailedDownloadLeavesTheOldFile() async throws {
        struct Offline: Error {}
        struct FailingDownloader: FileDownloading {
            func download(from _: URL, progress _: @escaping DownloadProgress) async throws -> URL {
                throw Offline()
            }
        }
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let release = try ReleaseInfo.decode(UpdateFixtures.latestRelease)
        let destination = folder.appendingPathComponent(release.diskImageName)
        try Data("old".utf8).write(to: destination)

        await #expect(throws: Offline.self) {
            try await UpdateDownloader(client: FailingDownloader()).download(release, to: folder)
        }
        #expect(try Data(contentsOf: destination) == Data("old".utf8))
    }
}
