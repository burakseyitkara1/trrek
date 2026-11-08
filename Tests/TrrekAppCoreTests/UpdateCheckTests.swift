import Foundation
import Testing
import TrrekAppCore

struct UpdateCheckPolicyTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let hour: TimeInterval = 3600

    private static func due(
        _ trigger: UpdateCheckTrigger,
        automatic: Bool = true,
        lastCheck: TimeInterval? = nil,
        lastFailure: TimeInterval? = nil
    ) -> Bool {
        UpdateCheckPolicy.shouldCheck(
            trigger: trigger,
            automatic: automatic,
            lastCheck: lastCheck.map { now.addingTimeInterval(-$0) },
            lastFailure: lastFailure.map { now.addingTimeInterval(-$0) },
            now: now
        )
    }

    @Test func manualAlwaysChecks() {
        #expect(Self.due(.manual, automatic: false, lastCheck: 1, lastFailure: 1))
        #expect(Self.due(.manual, lastCheck: 0))
    }

    @Test func automaticChecksAtMostOnceADay() {
        for trigger in [UpdateCheckTrigger.launch, .menuOpened, .wake] {
            #expect(trigger.isAutomatic)
            #expect(Self.due(trigger))
            #expect(!Self.due(trigger, lastCheck: 23 * Self.hour))
            #expect(Self.due(trigger, lastCheck: 24 * Self.hour))
            #expect(!Self.due(trigger, automatic: false))
            #expect(!Self.due(trigger, automatic: false, lastCheck: 48 * Self.hour))
        }
        #expect(!UpdateCheckTrigger.manual.isAutomatic)
    }

    @Test func aFailureWaitsAnHour() {
        #expect(!Self.due(.launch, lastFailure: 30 * 60))
        #expect(Self.due(.launch, lastFailure: Self.hour))
        #expect(!Self.due(.launch, lastCheck: 25 * Self.hour, lastFailure: 59 * 60))
        #expect(!Self.due(.launch, lastCheck: 2 * Self.hour, lastFailure: 2 * Self.hour))
    }

    @Test func aDateInTheFutureCountsAsOld() {
        #expect(Self.due(.wake, lastCheck: -Self.hour))
        #expect(Self.due(.wake, lastFailure: -60))
    }
}

@MainActor
@Suite(.serialized)
struct UpdateCheckerTests {
    private static let suiteName = "trrek.tests.update-check"

    private static func freshState() throws -> (UpdateStateStore, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (UpdateStateStore(defaults: defaults), defaults)
    }

    private static func version(_ text: String) throws -> SemanticVersion {
        try #require(SemanticVersion(text))
    }

    @Test func stateStoreRoundTrips() throws {
        let (state, defaults) = try Self.freshState()
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }
        #expect(state.lastCheck == nil)
        #expect(state.availableUpdate == nil)

        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let release = try ReleaseInfo.decode(UpdateFixtures.latestRelease)
        state.lastCheck = date
        state.lastFailure = date
        state.availableUpdate = release

        let reloaded = UpdateStateStore(defaults: defaults)
        #expect(reloaded.lastCheck == date)
        #expect(reloaded.lastFailure == date)
        #expect(reloaded.availableUpdate == release)
        // Kept apart from the settings blob.
        #expect(defaults.data(forKey: "settings") == nil)

        reloaded.availableUpdate = nil
        reloaded.lastFailure = nil
        #expect(state.availableUpdate == nil)
        #expect(state.lastFailure == nil)
        defaults.set(Data("x".utf8), forKey: "availableUpdate")
        #expect(state.availableUpdate == nil)
    }

    /// Anything running as the user can write the defaults; a stored update pointing elsewhere is not offered.
    @Test func aTamperedStoredUpdateIsIgnored() throws {
        let (state, defaults) = try Self.freshState()
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }
        let good = try ReleaseInfo.decode(UpdateFixtures.release(tag: "v9.0.0"))
        let elsewhere = try #require(URL(string: "https://example.com/trrek-v9.0.0.dmg"))
        let otherPage = try #require(URL(string: "https://example.com/releases"))
        let tampered = try [
            ReleaseInfo(version: good.version, pageURL: good.pageURL, diskImageURL: elsewhere, notes: ""),
            ReleaseInfo(version: good.version, pageURL: otherPage, diskImageURL: good.diskImageURL, notes: ""),
            // The image of another version under this version's name.
            ReleaseInfo(
                version: Self.version("9.0.1"),
                pageURL: good.pageURL,
                diskImageURL: good.diskImageURL,
                notes: ""
            )
        ]
        for release in tampered {
            state.availableUpdate = release
            #expect(defaults.data(forKey: "availableUpdate") != nil)
            #expect(state.availableUpdate == nil)
            let checker = try UpdateChecker(
                currentVersion: Self.version("0.2.0"),
                feed: FakeReleaseFeed(.success(Data())),
                state: state
            )
            #expect(checker.availableUpdate == nil)
        }
        state.availableUpdate = good
        #expect(state.availableUpdate == good)
    }

    @Test func aNewerReleaseIsStored() async throws {
        let (state, defaults) = try Self.freshState()
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }
        var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let feed = FakeReleaseFeed(.success(UpdateFixtures.latestRelease))
        let checker = try UpdateChecker(currentVersion: Self.version("0.2.0"), feed: feed, state: state) { now }
        var changes = 0
        checker.onStateChange = { changes += 1 }

        let first = await checker.check(.launch, automatic: true)
        let release = try ReleaseInfo.decode(UpdateFixtures.latestRelease)
        #expect(first == .available(release))
        #expect(checker.availableUpdate == release)
        #expect(checker.lastCheck == now)
        #expect(changes == 2)
        #expect(!checker.isChecking)

        // Within a day automatic triggers do nothing; a manual check runs.
        #expect(await checker.check(.menuOpened, automatic: true) == .skipped)
        #expect(await feed.calls == 1)
        #expect(await checker.check(.manual, automatic: true) == .available(release))

        // A day later the same version is found again.
        now.addTimeInterval(UpdateCheckPolicy.interval)
        #expect(await checker.check(.wake, automatic: true) == .available(release))
        #expect(await feed.calls == 3)
    }

    @Test func automaticChecksOffMeansNoRequest() async throws {
        let (state, defaults) = try Self.freshState()
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }
        let feed = FakeReleaseFeed(.success(UpdateFixtures.latestRelease))
        let checker = try UpdateChecker(currentVersion: Self.version("0.2.0"), feed: feed, state: state)

        #expect(!checker.isDue(.launch, automatic: false))
        #expect(await checker.check(.launch, automatic: false) == .skipped)
        #expect(await feed.calls == 0)
        #expect(checker.isDue(.manual, automatic: false))
    }

    @Test func upToDateClearsAStoredUpdate() async throws {
        let (state, defaults) = try Self.freshState()
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }
        state.availableUpdate = try ReleaseInfo.decode(UpdateFixtures.release(tag: "v9.0.0"))
        let feed = FakeReleaseFeed(.success(UpdateFixtures.latestRelease))
        let checker = try UpdateChecker(currentVersion: Self.version("0.3.0"), feed: feed, state: state)
        #expect(checker.availableUpdate != nil)

        let result = await checker.check(.manual, automatic: true)
        #expect(try result == .upToDate(latest: Self.version("0.3.0")))
        #expect(checker.availableUpdate == nil)
    }

    @Test func aStoredUpdateNoNewerThanTheRunningVersionIsForgotten() throws {
        let (state, defaults) = try Self.freshState()
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }
        state.availableUpdate = try ReleaseInfo.decode(UpdateFixtures.latestRelease)
        let feed = FakeReleaseFeed(.success(Data()))

        _ = try UpdateChecker(currentVersion: Self.version("0.2.0"), feed: feed, state: state)
        #expect(state.availableUpdate != nil)
        _ = try UpdateChecker(currentVersion: Self.version("0.3.0"), feed: feed, state: state)
        #expect(state.availableUpdate == nil)
    }

    @Test func aFailureIsReportedAndRetriedAfterAnHour() async throws {
        let (state, defaults) = try Self.freshState()
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }
        var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let feed = FakeReleaseFeed(.failure(URLError(.notConnectedToInternet)))
        let checker = try UpdateChecker(currentVersion: Self.version("0.2.0"), feed: feed, state: state) { now }

        let result = await checker.check(.launch, automatic: true)
        guard case let .failed(message) = result else {
            Issue.record("expected a failure, got \(result)")
            return
        }
        #expect(!message.isEmpty)
        #expect(checker.lastCheck == nil)
        #expect(state.lastFailure == now)
        #expect(!checker.isDue(.menuOpened, automatic: true))

        now.addTimeInterval(UpdateCheckPolicy.retryInterval)
        await feed.set(.success(UpdateFixtures.latestRelease))
        #expect(checker.isDue(.menuOpened, automatic: true))
        guard case .available = await checker.check(.menuOpened, automatic: true) else {
            Issue.record("expected an update")
            return
        }
        #expect(state.lastFailure == nil)
        #expect(checker.lastCheck == now)
    }

    @Test func feedErrorsUseTheirOwnMessage() async throws {
        let (state, defaults) = try Self.freshState()
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }
        let feed = FakeReleaseFeed(.success(Data("{}".utf8)))
        let checker = try UpdateChecker(currentVersion: Self.version("0.2.0"), feed: feed, state: state)
        #expect(await checker.check(.manual, automatic: true)
            == .failed(message: ReleaseFeedError.missingTag.message))
        #expect(UpdateChecker.message(for: ReleaseFeedError.httpStatus(404)) == ReleaseFeedError.httpStatus(404)
            .message)
    }

    @Test func onlySuccessfulHTTPAnswersAreRead() throws {
        let url = try #require(URL(string: "https://example.com"))
        let ok = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        let missing = try #require(HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil))
        try ReleaseFeedClient.requireSuccess(ok)
        #expect(throws: ReleaseFeedError.httpStatus(404)) { try ReleaseFeedClient.requireSuccess(missing) }
        let plain = URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        #expect(throws: ReleaseFeedError.malformed) { try ReleaseFeedClient.requireSuccess(plain) }
    }
}

struct UpdateSettingTests {
    @Test func automaticChecksDefaultOnAndRoundTrip() throws {
        #expect(Settings().checkForUpdatesAutomatically)
        let old = try JSONDecoder().decode(Settings.self, from: Data(#"{"precision": true}"#.utf8))
        #expect(old.checkForUpdatesAutomatically)

        var settings = Settings()
        settings.checkForUpdatesAutomatically = false
        let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        #expect(!decoded.checkForUpdatesAutomatically)
        #expect(settings.resetToDefaults(backlightAvailable: true).checkForUpdatesAutomatically)
    }

    @Test func theSettingIsExported() throws {
        var settings = Settings()
        settings.checkForUpdatesAutomatically = false
        let data = try SettingsDocument.encode(settings)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let fields = try #require(object["settings"] as? [String: Any])
        #expect(fields["checkForUpdatesAutomatically"] as? Bool == false)
        #expect(try !SettingsDocument.decode(data).checkForUpdatesAutomatically)
    }
}
