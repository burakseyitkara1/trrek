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

/// Download progress: the bytes received so far and the bytes expected (`-1` while unknown). Called on a background
/// queue.
public typealias DownloadProgress = @Sendable (_ received: Int64, _ expected: Int64) -> Void

/// Downloads a file to a temporary location and returns it; replaced by a fake in tests.
public protocol FileDownloading: Sendable {
    func download(from url: URL, progress: @escaping DownloadProgress) async throws -> URL
}

/// Downloads with an ephemeral session, like the feed, through a session delegate that reports progress.
public struct SessionFileDownloader: FileDownloading {
    /// A slow connection may stall this long between packets (release downloads were seen pausing for more than
    /// the feed's 15 s at 30 KB/s) …
    public static let idleTimeout: TimeInterval = 60
    /// … and take this long for the whole file.
    public static let resourceTimeout: TimeInterval = 600

    private let configuration: @Sendable () -> URLSessionConfiguration

    /// `configuration` is for tests (a stub protocol); the default is the feed's ephemeral configuration.
    public init(configuration: (@Sendable () -> URLSessionConfiguration)? = nil) {
        self.configuration = configuration ?? {
            ReleaseFeedClient.configuration(
                requestTimeout: SessionFileDownloader.idleTimeout,
                resourceTimeout: SessionFileDownloader.resourceTimeout
            )
        }
    }

    public func download(from url: URL, progress: @escaping DownloadProgress) async throws -> URL {
        let delegate = DownloadDelegate(progress: progress)
        let session = URLSession(configuration: configuration(), delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        var request = ReleaseFeedClient.request(url: url)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = Self.idleTimeout
        let task = session.downloadTask(with: request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.start(continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }
}

/// Reports a download task's progress, keeps its file and resumes the waiting call once.
final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: DownloadProgress
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, any Error>?
    private var result: Result<URL, any Error>?
    /// The last reported whole percent (`-1` for an unknown size), so at most about a hundred reports are made.
    private var reported: Int?

    init(progress: @escaping DownloadProgress) {
        self.progress = progress
    }

    func start(_ continuation: CheckedContinuation<URL, any Error>) {
        lock.withLock { self.continuation = continuation }
    }

    func urlSession(
        _: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let step = Self.step(received: totalBytesWritten, expected: totalBytesExpectedToWrite)
        let isNew = lock.withLock {
            guard reported != step else { return false }
            reported = step
            return true
        }
        if isNew {
            progress(totalBytesWritten, totalBytesExpectedToWrite)
        }
    }

    /// The whole percent received, or `-1` while the size is unknown.
    static func step(received: Int64, expected: Int64) -> Int {
        guard expected > 0 else { return -1 }
        return Int(min(max(received, 0), expected) * 100 / expected)
    }

    /// The file at `location` is deleted when this returns, so it is moved to a file of our own first.
    func urlSession(_: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let outcome: Result<URL, any Error>
        do {
            guard let response = downloadTask.response else { throw ReleaseFeedError.malformed }
            try ReleaseFeedClient.requireSuccess(response)
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("trrek-download-\(UUID().uuidString)")
            try FileManager.default.moveItem(at: location, to: file)
            outcome = .success(file)
        } catch {
            outcome = .failure(error)
        }
        lock.withLock { result = outcome }
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let (continuation, result) = lock.withLock {
            let pair = (self.continuation, self.result)
            self.continuation = nil
            return pair
        }
        if let error {
            if case let .success(file) = result {
                try? FileManager.default.removeItem(at: file)
            }
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume(with: result ?? .failure(ReleaseFeedError.malformed))
        }
    }
}

/// A downloaded disk image.
public struct DownloadedDiskImage: Equatable, Sendable {
    public let file: URL
    /// Whether the quarantine attribute was set, as on a browser download. Only logged (when it could not be set):
    /// trrek checks the signature and notarization itself before installing.
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

    /// Downloads `release`'s disk image to `folder/trrek-vX.Y.Z.dmg` (creating the folder) and marks it as
    /// downloaded from the internet, like a browser download.
    public func download(
        _ release: ReleaseInfo,
        to folder: URL,
        progress: @escaping DownloadProgress = { _, _ in }
    ) async throws -> DownloadedDiskImage {
        let temporary = try await client.download(from: release.diskImageURL, progress: progress)
        let destination = folder.appendingPathComponent(release.diskImageName)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
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
