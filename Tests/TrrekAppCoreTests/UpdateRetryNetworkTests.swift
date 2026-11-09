import Foundation
import Testing
@testable import TrrekAppCore

/// The feed client and the downloader against a stub protocol that answers from a script: retried answers, the
/// waits between them and the files left behind. Part of the serialized session downloader suite, so no other
/// download runs meanwhile and the temporary folder's downloads can be compared.
extension SessionFileDownloaderTests {
    enum Step {
        case status(Int, headers: [String: String] = [:])
        case failure(URLError.Code)
    }

    final class ScriptedStub: URLProtocol, @unchecked Sendable {
        private static let lock = NSLock()
        private nonisolated(unsafe) static var steps: [Step] = []
        private nonisolated(unsafe) static var served = 0
        static let body = Data(repeating: 9, count: 120_000)

        static func play(_ script: [Step]) {
            lock.withLock {
                steps = script
                served = 0
            }
        }

        static var requests: Int {
            lock.withLock { served }
        }

        override static func canInit(with _: URLRequest) -> Bool {
            true
        }

        override static func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            let step: Step = Self.lock.withLock {
                defer { Self.served += 1 }
                return Self.served < Self.steps.count ? Self.steps[Self.served] : .status(200)
            }
            switch step {
            case let .failure(code):
                client?.urlProtocol(self, didFailWithError: URLError(code))
            case let .status(status, headers):
                let body = status == 200 ? Self.body : Data("<html>Gateway Timeout</html>".utf8)
                var fields = headers
                fields["Content-Length"] = "\(body.count)"
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: fields
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: body)
                client?.urlProtocolDidFinishLoading(self)
            }
        }

        override func stopLoading() {}
    }

    @Sendable private static func scriptedConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScriptedStub.self]
        return configuration
    }

    private static func scriptedDownloader(_ waits: RecordedWaits) -> UpdateDownloader {
        UpdateDownloader(client: SessionFileDownloader(configuration: scriptedConfiguration), retry: waits.policy)
    }

    private static func feed(_ waits: RecordedWaits) -> ReleaseFeedClient {
        ReleaseFeedClient(configuration: scriptedConfiguration, retry: waits.policy)
    }

    private final class RetryReports: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [(Int64, Int64)] = []

        func add(_ received: Int64, _ expected: Int64) {
            lock.withLock { values.append((received, expected)) }
        }

        var all: [(Int64, Int64)] {
            lock.withLock { values }
        }
    }

    private static func retryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("trrek-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// The downloads (`trrek-download-…`) in the temporary folder.
    private static func retryDownloadsLeft() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path))
        return Set((names ?? []).filter { $0.hasPrefix("trrek-download-") })
    }

    // MARK: - Feed

    @Test func theFeedSucceedsAfterTwoGatewayTimeouts() async throws {
        let waits = RecordedWaits()
        ScriptedStub.play([.status(504), .status(504), .status(200)])
        #expect(try await Self.feed(waits).latestRelease() == ScriptedStub.body)
        #expect(ScriptedStub.requests == 3)
        #expect(waits.all == [.seconds(2), .seconds(5)])
    }

    @Test func theFeedFailsAsServerUnavailableAfterThreeGatewayTimeouts() async throws {
        let waits = RecordedWaits()
        ScriptedStub.play([.status(504), .status(504), .status(504), .status(200)])
        let error = await #expect(throws: ReleaseFeedError.httpStatus(504)) {
            _ = try await Self.feed(waits).latestRelease()
        }
        #expect(try UpdateFailure(#require(error)) == .serverUnavailable)
        #expect(ScriptedStub.requests == 3)
        #expect(waits.all.count == 2)
    }

    @Test func theFeedFailsAtOnceOnNotFound() async {
        let waits = RecordedWaits()
        ScriptedStub.play([.status(404), .status(200)])
        await #expect(throws: ReleaseFeedError.httpStatus(404)) {
            _ = try await Self.feed(waits).latestRelease()
        }
        #expect(ScriptedStub.requests == 1)
        #expect(waits.all.isEmpty)
    }

    @Test func theFeedSucceedsAfterATimeout() async throws {
        let waits = RecordedWaits()
        ScriptedStub.play([.failure(.timedOut), .status(200)])
        #expect(try await Self.feed(waits).latestRelease() == ScriptedStub.body)
        #expect(ScriptedStub.requests == 2)
        #expect(waits.all == [.seconds(2)])
    }

    @Test func theFeedWaitsWhatRetryAfterAsks() async throws {
        let waits = RecordedWaits()
        ScriptedStub.play([.status(503, headers: ["Retry-After": "7"]), .status(200)])
        #expect(try await Self.feed(waits).latestRelease() == ScriptedStub.body)
        #expect(waits.all == [.seconds(7)])

        ScriptedStub.play([.status(429, headers: ["Retry-After": "120"]), .status(200)])
        await #expect(throws: ReleaseFeedError.httpStatus(429, retryAfter: 120)) {
            _ = try await Self.feed(waits).latestRelease()
        }
        #expect(ScriptedStub.requests == 1)
    }

    // MARK: - Download

    @Test func theDownloadSucceedsAfterTwoGatewayTimeouts() async throws {
        let folder = try Self.retryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let release = try ReleaseInfo.decode(UpdateFixtures.latestRelease)
        let waits = RecordedWaits()
        let reports = RetryReports()
        let downloader = Self.scriptedDownloader(waits)
        let before = Self.retryDownloadsLeft()
        ScriptedStub.play([.status(504), .status(504), .status(200)])

        let image = try await downloader.download(release, to: folder) { reports.add($0, $1) }

        #expect(try Data(contentsOf: image.file) == ScriptedStub.body)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == [release.diskImageName])
        #expect(ScriptedStub.requests == 3)
        #expect(waits.all == [.seconds(2), .seconds(5)])
        // Each retry starts the progress over; the 504 pages are never reported as progress.
        let size = Int64(ScriptedStub.body.count)
        let all = reports.all
        #expect(all.prefix(2).allSatisfy { $0 == (0, -1) })
        #expect(all.dropFirst(2).allSatisfy { $0.1 == size && $0.0 > 0 })
        #expect(all.count(where: { $0 == (0, -1) }) == 2)
        #expect(all.last.map { $0 == (size, size) } == true)
        #expect(Self.retryDownloadsLeft().subtracting(before).isEmpty)
    }

    /// An error answer's page is downloaded by the task but is no progress of the disk image.
    @Test func anErrorPageReportsNoProgress() async throws {
        let reports = RetryReports()
        let downloader = SessionFileDownloader(configuration: Self.scriptedConfiguration)
        let url = try #require(URL(string: "https://github.com/burakseyitkara1/trrek/releases/download/v0.3.0/x.dmg"))
        ScriptedStub.play([.status(504)])
        await #expect(throws: ReleaseFeedError.httpStatus(504)) {
            _ = try await downloader.download(from: url) { reports.add($0, $1) }
        }
        #expect(reports.all.isEmpty)
    }

    @Test func aDownloadThatKeepsFailingLeavesNoFile() async throws {
        let folder = try Self.retryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let release = try ReleaseInfo.decode(UpdateFixtures.latestRelease)
        let waits = RecordedWaits()
        let downloader = Self.scriptedDownloader(waits)
        let before = Self.retryDownloadsLeft()
        ScriptedStub.play([.status(504), .failure(.networkConnectionLost), .status(502), .status(200)])

        let error = await #expect(throws: ReleaseFeedError.httpStatus(502)) {
            _ = try await downloader.download(release, to: folder)
        }
        #expect(try UpdateFailure(#require(error)) == .serverUnavailable)
        #expect(ScriptedStub.requests == 3)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        #expect(Self.retryDownloadsLeft().subtracting(before).isEmpty)
    }

    @Test func aDownloadSucceedsAfterATimeoutAndFailsAtOnceOnNotFound() async throws {
        let folder = try Self.retryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let release = try ReleaseInfo.decode(UpdateFixtures.latestRelease)
        let waits = RecordedWaits()
        let downloader = Self.scriptedDownloader(waits)

        ScriptedStub.play([.failure(.timedOut), .status(200)])
        let image = try await downloader.download(release, to: folder)
        #expect(try Data(contentsOf: image.file) == ScriptedStub.body)
        #expect(ScriptedStub.requests == 2)
        try FileManager.default.removeItem(at: image.file)

        ScriptedStub.play([.status(404), .status(200)])
        await #expect(throws: ReleaseFeedError.httpStatus(404)) {
            _ = try await downloader.download(release, to: folder)
        }
        #expect(ScriptedStub.requests == 1)
        #expect(waits.all == [.seconds(2)])
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    /// The size limit still applies to every attempt, and a refused download is not retried.
    @Test func aRetriedDownloadKeepsTheSizeLimit() async throws {
        let folder = try Self.retryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let release = try ReleaseInfo.decode(UpdateFixtures.latestRelease)
        let waits = RecordedWaits()
        let small = SessionFileDownloader(configuration: Self.scriptedConfiguration, maximumSize: 1000)
        ScriptedStub.play([.status(503), .status(200), .status(200)])
        await #expect(throws: ReleaseFeedError.tooLarge) {
            _ = try await UpdateDownloader(client: small, retry: waits.policy).download(release, to: folder)
        }
        #expect(ScriptedStub.requests == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }
}
