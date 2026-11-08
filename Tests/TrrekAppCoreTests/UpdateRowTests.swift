import Foundation
import Testing
@testable import TrrekAppCore

/// The update row's state machine and texts.
struct UpdateRowStateTests {
    private static let version = SemanticVersion(major: 0, minor: 4, patch: 0)

    @Test func aClickStartsTheDownloadAndProgressMovesInWholePercents() {
        var row = UpdateRowState.available(Self.version)
        #expect(row.isClickable && !row.isBusy)
        let step1 = row.start()

        #expect(step1)
        #expect(row == .downloading(Self.version, progress: nil))
        #expect(row.isBusy && !row.isClickable)
        let step2 = row.start()

        #expect(!step2)

        let step3 = row.progress(received: 10, expected: -1)

        #expect(!step3)
        let step4 = row.progress(received: 10, expected: 1000)

        #expect(step4)
        #expect(row == .downloading(Self.version, progress: 0.01))
        // Less than a whole percent more: nothing to redraw.
        let step5 = row.progress(received: 15, expected: 1000)

        #expect(!step5)
        let step6 = row.progress(received: 500, expected: 1000)

        #expect(step6)
        #expect(row == .downloading(Self.version, progress: 0.5))
        let step7 = row.progress(received: 2000, expected: 1000)

        #expect(step7)
        #expect(row == .downloading(Self.version, progress: 1))

        row.downloaded()
        #expect(row == .installing(Self.version))
        #expect(row.isBusy)
        // A late progress report does not go back to downloading.
        let step8 = row.progress(received: 1000, expected: 1000)

        #expect(!step8)
        #expect(row == .installing(Self.version))
    }

    @Test func failuresAndFallbacks() {
        var row = UpdateRowState.installing(Self.version)
        row.fail()
        #expect(row == .failed(Self.version))
        #expect(row.isClickable)
        let step9 = row.start()

        #expect(step9)
        #expect(row == .downloading(Self.version, progress: nil))

        row.fallBackToBrowser()
        #expect(row == .browser(Self.version))
        let step10 = row.start()

        #expect(!step10)
        row.installedWithoutRelaunch()
        #expect(row == .relaunch(Self.version))
        let step11 = row.start()

        #expect(!step11)
        var available = UpdateRowState.available(Self.version)
        available.downloaded()
        #expect(available == .available(Self.version))
    }

    @Test func texts() {
        let ver = Self.version
        #expect(UpdateRowState.available(ver).title == "Update Available: trrek 0.4.0")
        #expect(UpdateRowState.downloading(ver, progress: 0.3).title == "Downloading trrek 0.4.0…")
        #expect(UpdateRowState.installing(ver).title == "Installing trrek 0.4.0…")
        #expect(UpdateRowState.failed(ver).title == "Update Failed — Try Again")
        #expect(UpdateRowState.browser(ver).title == "Update in Browser…")
        #expect(UpdateRowState.relaunch(ver).title == "Relaunch to Finish Updating")

        #expect(UpdateRowState.available(ver).statusText == "trrek 0.4.0 is available")
        #expect(UpdateRowState.available(ver).actionTitle == "Update Now")
        #expect(UpdateRowState.failed(ver).actionTitle == "Try Again")
        #expect(UpdateRowState.browser(ver).actionTitle == "Update in Browser…")
        #expect(UpdateRowState.relaunch(ver).statusText == "trrek 0.4.0 is installed")
        #expect(UpdateRowState.downloading(ver, progress: nil).actionTitle == nil)
        #expect(UpdateRowState.installing(ver).actionTitle == nil)
    }
}

/// The session downloader against a stub protocol: progress, the file and HTTP errors.
@Suite(.serialized)
struct SessionFileDownloaderTests {
    final class Stub: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var status = 200
        static let body = Data(repeating: 7, count: 300_000)

        override static func canInit(with _: URLRequest) -> Bool {
            true
        }

        override static func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: Self.status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Length": "\(Self.body.count)"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            var offset = 0
            while offset < Self.body.count {
                let end = min(offset + 50000, Self.body.count)
                client?.urlProtocol(self, didLoad: Self.body.subdata(in: offset ..< end))
                offset = end
            }
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private final class Reports: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [(Int64, Int64)] = []

        func add(_ received: Int64, _ expected: Int64) {
            lock.withLock { values.append((received, expected)) }
        }

        var all: [(Int64, Int64)] {
            lock.withLock { values }
        }
    }

    private static let downloader = SessionFileDownloader {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        return configuration
    }

    private static let url =
        URL(string: "https://github.com/burakseyitkara1/trrek-releases/releases/download/v0.4.0/trrek-v0.4.0.dmg")!

    @Test func reportsProgressAndKeepsTheFile() async throws {
        Stub.status = 200
        let reports = Reports()
        let file = try await Self.downloader.download(from: Self.url) { reports.add($0, $1) }
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(try Data(contentsOf: file) == Stub.body)
        let all = reports.all
        #expect(!all.isEmpty)
        #expect(all.last?.0 == Int64(Stub.body.count))
        #expect(all.allSatisfy { $0.1 == Int64(Stub.body.count) })
        #expect(zip(all, all.dropFirst()).allSatisfy { $0.0 <= $1.0 })
    }

    @Test func anHTTPErrorIsThrownAndLeavesNoFile() async throws {
        Stub.status = 404
        defer { Stub.status = 200 }
        await #expect(throws: ReleaseFeedError.httpStatus(404)) {
            _ = try await Self.downloader.download(from: Self.url) { _, _ in }
        }
    }

    /// Progress is reported once per whole percent (and once while the size is unknown).
    @Test func progressStepsAreWholePercents() {
        #expect(DownloadDelegate.step(received: 0, expected: -1) == -1)
        #expect(DownloadDelegate.step(received: 999, expected: 100_000) == 0)
        #expect(DownloadDelegate.step(received: 1000, expected: 100_000) == 1)
        #expect(DownloadDelegate.step(received: 200_000, expected: 100_000) == 100)
        let steps = Set(stride(from: 0, through: 1_000_000, by: 1000).map {
            DownloadDelegate.step(received: Int64($0), expected: 1_000_000)
        })
        #expect(steps.count == 101)
    }

    @Test func theFolderIsCreated() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("trrek-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Caches/Updates")
        let release = try ReleaseInfo.decode(UpdateFixtures.latestRelease)
        let image = try await UpdateDownloader(client: FakeFileDownloader(contents: Data("dmg".utf8)))
            .download(release, to: folder)
        #expect(image.file.deletingLastPathComponent().path == folder.path)
        #expect(FileManager.default.fileExists(atPath: image.file.path))
    }
}
