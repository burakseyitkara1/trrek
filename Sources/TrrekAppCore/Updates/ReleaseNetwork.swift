import Foundation
import TrrekEngine

/// The releases API's latest release of the public releases repository.
///
/// Each request uses its own ephemeral session (no cookies, no cache, no stored credentials) that is invalidated
/// afterwards, and sends only the `Accept` and `User-Agent` headers.
public struct ReleaseFeedClient: ReleaseFeed {
    public static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/burakseyitkara1/trrek-releases/releases/latest"
    )!
    public static let timeout: TimeInterval = 15

    public init() {}

    /// The request for the latest release; the user agent names the running version, never an assumed one.
    public static func request(url: URL = latestReleaseURL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("trrek/\(TrrekVersion.string)", forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = false
        return request
    }

    /// An ephemeral configuration without cookies, cache or credentials. `requestTimeout` is how long the
    /// connection may stay idle, `resourceTimeout` how long the whole transfer may take.
    public static func configuration(
        requestTimeout: TimeInterval = timeout,
        resourceTimeout: TimeInterval
    ) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        return configuration
    }

    public func latestRelease() async throws -> Data {
        let session = URLSession(configuration: Self.configuration(resourceTimeout: Self.timeout))
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: Self.request())
        try Self.requireSuccess(response)
        return data
    }

    /// Throws `ReleaseFeedError.httpStatus` unless `response` is HTTP 200.
    public static func requireSuccess(_ response: URLResponse) throws(ReleaseFeedError) {
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw .malformed }
        guard status == 200 else { throw .httpStatus(status) }
    }
}

/// Downloads a file to a temporary location and returns it; replaced by a fake in tests.
public protocol FileDownloading: Sendable {
    func download(from url: URL) async throws -> URL
}

/// Downloads with an ephemeral session, like the feed.
public struct SessionFileDownloader: FileDownloading {
    /// A slow connection may stall this long between packets (release downloads were seen pausing for more than
    /// the feed's 15 s at 30 KB/s) …
    public static let idleTimeout: TimeInterval = 60
    /// … and take this long for the whole file.
    public static let resourceTimeout: TimeInterval = 600

    public init() {}

    public func download(from url: URL) async throws -> URL {
        let configuration = ReleaseFeedClient.configuration(
            requestTimeout: Self.idleTimeout,
            resourceTimeout: Self.resourceTimeout
        )
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        var request = ReleaseFeedClient.request(url: url)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = Self.idleTimeout
        // The async API leaves the temporary file in place; it is moved or deleted by the caller or here.
        let (file, response) = try await session.download(for: request)
        do {
            try ReleaseFeedClient.requireSuccess(response)
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
        return file
    }
}

/// A downloaded disk image.
public struct DownloadedDiskImage: Equatable, Sendable {
    public let file: URL
    /// Whether the quarantine attribute was set; without it the system would not check the app inside when it is
    /// first opened, so the image is only shown in Finder rather than opened.
    public let isQuarantined: Bool

    public init(file: URL, isQuarantined: Bool) {
        self.file = file
        self.isQuarantined = isQuarantined
    }
}

/// Downloads a release's disk image into a folder, replacing a file of the same name.
public struct UpdateDownloader: Sendable {
    private let client: any FileDownloading

    public init(client: any FileDownloading = SessionFileDownloader()) {
        self.client = client
    }

    /// Downloads `release`'s disk image to `folder/trrek-vX.Y.Z.dmg` and marks it as downloaded from the internet,
    /// so the system checks the app inside when it is first opened.
    public func download(_ release: ReleaseInfo, to folder: URL) async throws -> DownloadedDiskImage {
        let temporary = try await client.download(from: release.diskImageURL)
        let destination = folder.appendingPathComponent(release.diskImageName)
        do {
            try Self.move(temporary, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        let quarantined = Self.markQuarantined(destination, source: release.diskImageURL)
        return DownloadedDiskImage(file: destination, isQuarantined: quarantined)
    }

    /// Moves `source` to `destination`, removing a file already there.
    static func move(_ source: URL, to destination: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: destination.path) {
            try manager.removeItem(at: destination)
        }
        try manager.moveItem(at: source, to: destination)
    }

    /// Adds the quarantine attribute a browser download gets; returns whether it was set.
    static func markQuarantined(_ file: URL, source: URL) -> Bool {
        var values = URLResourceValues()
        values.quarantineProperties = [
            "LSQuarantineAgentName": "trrek",
            "LSQuarantineType": "LSQuarantineTypeWebDownload",
            "LSQuarantineDataURL": source.absoluteString
        ]
        var file = file
        do {
            try file.setResourceValues(values)
            return true
        } catch {
            appLogger.error("download quarantine failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }
}
