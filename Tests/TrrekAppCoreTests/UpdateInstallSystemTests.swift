import Foundation
import Testing
@testable import TrrekAppCore

/// The system steps of the in-place install on temporary folders; nothing outside them is touched.
struct UpdateInstallSystemTests {
    private static func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("trrek-system-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A folder shaped like an app bundle, with `marker` as its version.
    private static func makeBundle(at url: URL, marker: String) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": AppIdentity.bundleID, "CFBundleShortVersionString": marker]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }

    private static func quarantine(_ path: String) -> Bool {
        getxattr(path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }

    @Test func attachIsReadOnlyHiddenAndAtThePrivateMountPoint() {
        let commands = DiskImageAppExtractor.attachCommands(image: "/d/i.dmg", mountPoint: "/t/m")
        #expect(commands.map(\.0) == ["/usr/sbin/diskutil", "/usr/bin/hdiutil"])
        let modern = commands[0].1
        #expect(modern.starts(with: ["image", "attach", "--plist"]))
        #expect(modern.contains("--readOnly") && modern.contains("--nobrowse"))
        #expect(modern.suffix(3) == ["--mountPoint", "/t/m", "/d/i.dmg"])
        let legacy = commands[1].1
        #expect(["-readonly", "-nobrowse", "-noautoopen", "-plist"].allSatisfy(legacy.contains))
        #expect(legacy.suffix(3) == ["-mountpoint", "/t/m", "/d/i.dmg"])
    }

    @Test func theWholeDiskIsFoundInTheAttachOutput() throws {
        func output(_ entries: [String]) throws -> Data {
            let entities = entries.map { ["dev-entry": $0, "content-hint": "x"] }
            return try PropertyListSerialization.data(
                fromPropertyList: ["system-entities": entities],
                format: .xml,
                options: 0
            )
        }
        #expect(try DiskImageAppExtractor.wholeDisk(inAttachOutput: output(["disk8s1", "disk8", "disk9s1"])) == "disk8")
        #expect(try DiskImageAppExtractor.wholeDisk(inAttachOutput: output(["/dev/disk12", "/dev/disk12s1"]))
            == "/dev/disk12")
        #expect(try DiskImageAppExtractor.wholeDisk(inAttachOutput: output(["disk", "diskX"])) == nil)
        #expect(DiskImageAppExtractor.wholeDisk(inAttachOutput: Data("not a plist".utf8)) == nil)
    }

    @Test func aMissingOrLinkedAppIsNotCopied() async throws {
        let folder = try Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let volume = folder.appendingPathComponent("volume")
        try FileManager.default.createDirectory(at: volume, withIntermediateDirectories: true)
        await #expect(throws: DiskImageError.noApp) {
            try await DiskImageAppExtractor.copyApp(from: volume, into: folder)
        }
        let elsewhere = folder.appendingPathComponent("elsewhere.app")
        try Self.makeBundle(at: elsewhere, marker: "1.0.0")
        try FileManager.default.createSymbolicLink(
            at: volume.appendingPathComponent("trrek.app"),
            withDestinationURL: elsewhere
        )
        await #expect(throws: DiskImageError.noApp) {
            try await DiskImageAppExtractor.copyApp(from: volume, into: folder)
        }
    }

    @Test func theAppIsCopiedWithDitto() async throws {
        let folder = try Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let volume = folder.appendingPathComponent("volume")
        try Self.makeBundle(at: volume.appendingPathComponent("trrek.app"), marker: "0.4.0")
        let staging = folder.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let app = try await DiskImageAppExtractor.copyApp(from: volume, into: staging)
        #expect(app.path == staging.appendingPathComponent("trrek.app").path)
        #expect(CodeSignatureVerifier.identity(of: app) == (AppIdentity.bundleID, "0.4.0"))
    }

    @Test func theReplacerSwapsTheBundleAndDropsQuarantine() async throws {
        let folder = try Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let installed = folder.appendingPathComponent("Applications/trrek.app")
        try Self.makeBundle(at: installed, marker: "0.3.0")
        let staged = folder.appendingPathComponent("staging/trrek.app")
        try Self.makeBundle(at: staged, marker: "0.4.0")
        let plist = staged.appendingPathComponent("Contents/Info.plist").path
        for path in [staged.path, plist] {
            #expect(setxattr(path, "com.apple.quarantine", "0083;0;trrek;", 13, 0, XATTR_NOFOLLOW) == 0)
        }

        // A backup an interrupted install left is replaced, never kept.
        let stale = BundleReplacer.backup(for: installed)
        try Self.makeBundle(at: stale, marker: "0.1.0")

        let replacer = BundleReplacer()
        await replacer.removeQuarantine(in: staged)
        let backup = try await replacer.swap(installed, with: staged)

        #expect(backup.path == stale.path)
        #expect(CodeSignatureVerifier.identity(of: installed).1 == "0.4.0")
        #expect(CodeSignatureVerifier.identity(of: backup).1 == "0.3.0")
        #expect(!FileManager.default.fileExists(atPath: staged.path))
        #expect(!Self.quarantine(installed.path))
        #expect(!Self.quarantine(installed.appendingPathComponent("Contents/Info.plist").path))
        await replacer.removeBackup(next: installed)
        let left = try FileManager.default.contentsOfDirectory(atPath: installed.deletingLastPathComponent().path)
        #expect(left == ["trrek.app"])
    }

    @Test func theBackupCanBePutBack() async throws {
        let folder = try Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let installed = folder.appendingPathComponent("Applications/trrek.app")
        try Self.makeBundle(at: installed, marker: "0.3.0")
        let staged = folder.appendingPathComponent("staging/trrek.app")
        try Self.makeBundle(at: staged, marker: "0.4.0")
        let replacer = BundleReplacer()
        let backup = try await replacer.swap(installed, with: staged)

        try await replacer.restore(installed, from: backup)

        #expect(CodeSignatureVerifier.identity(of: installed).1 == "0.3.0")
        #expect(!FileManager.default.fileExists(atPath: backup.path))
    }

    /// The swap fails after the staged app exists (the folder became read-only, so no backup can be made): the
    /// installed app is untouched.
    @Test func aFailedSwapKeepsTheInstalledApp() async throws {
        let folder = try Self.temporaryFolder()
        let applications = folder.appendingPathComponent("Applications")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: applications.path)
            try? FileManager.default.removeItem(at: folder)
        }
        let installed = applications.appendingPathComponent("trrek.app")
        try Self.makeBundle(at: installed, marker: "0.3.0")
        let staged = folder.appendingPathComponent("staging/trrek.app")
        try Self.makeBundle(at: staged, marker: "0.4.0")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: applications.path)

        await #expect(throws: (any Error).self) {
            _ = try await BundleReplacer().swap(installed, with: staged)
        }
        #expect(CodeSignatureVerifier.identity(of: installed).1 == "0.3.0")
        #expect(FileManager.default.fileExists(atPath: staged.path))
    }

    /// When a failed swap left the bundle missing, the previous app is moved back from the backup.
    @Test func aMissingBundleIsRecoveredFromTheBackup() throws {
        let folder = try Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let installed = folder.appendingPathComponent("trrek.app")
        try Self.makeBundle(at: BundleReplacer.backup(for: installed), marker: "0.3.0")
        BundleReplacer.recover(installed, after: CocoaError(.fileWriteUnknown))
        #expect(CodeSignatureVerifier.identity(of: installed).1 == "0.3.0")
        #expect(!FileManager.default.fileExists(atPath: BundleReplacer.backup(for: installed).path))
    }

    /// Leftover mount point folders of an interrupted run are removed; other folders are kept.
    @Test func leftoverMountPointsAreRemoved() async throws {
        let folder = try Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let leftover = folder.appendingPathComponent("trrek-update-1234")
        let other = folder.appendingPathComponent("other")
        for url in [leftover, other] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        #expect(!DiskImageAppExtractor.isMountPoint(leftover))
        await DiskImageAppExtractor(temporaryFolder: folder).cleanUpLeftovers()
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["other"])
        #expect(DiskImageAppExtractor.isMountPoint(URL(fileURLWithPath: "/dev")))
    }

    /// An image not signed by the release team is refused before it is attached.
    @Test func anUnsignedDiskImageIsNotAttached() async throws {
        let folder = try Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appendingPathComponent("trrek-v9.9.9.dmg")
        try Data("not an image".utf8).write(to: image)
        await #expect(throws: UpdateVerificationFailure.signature) {
            try await DiskImageAppExtractor(temporaryFolder: folder).extractApp(from: image, into: folder)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["trrek-v9.9.9.dmg"])
    }

    @Test func theLocationFactsOfAFolder() throws {
        let folder = try Self.temporaryFolder()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
            try? FileManager.default.removeItem(at: folder)
        }
        let app = folder.appendingPathComponent("trrek.app")
        try Self.makeBundle(at: app, marker: "0.3.0")
        let facts = SystemInstallLocation().facts(for: app)
        #expect(facts.isAppBundle && facts.isWritable)
        #expect(!facts.isOnDiskImage && !facts.isOnReadOnlyVolume)
        #expect(UpdateInstallPolicy.issue(for: facts) == nil)

        #expect(!SystemInstallLocation().facts(for: folder).isAppBundle)
        let bare = folder.appendingPathComponent("bare.app")
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        #expect(!SystemInstallLocation().facts(for: bare).isAppBundle)

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        #expect(UpdateInstallPolicy.issue(for: SystemInstallLocation().facts(for: app)) == .notWritable)
    }

    @Test func anUnsignedAppFailsTheSignatureCheck() async throws {
        let folder = try Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = folder.appendingPathComponent("trrek.app")
        try Self.makeBundle(at: app, marker: "0.4.0")
        let failure = await CodeSignatureVerifier().verify(
            app,
            expected: SemanticVersion(major: 0, minor: 4, patch: 0),
            current: SemanticVersion(major: 0, minor: 3, patch: 0)
        )
        #expect(failure == .signature)
    }

    @Test func commandsReportTheirStatusAndOutput() async throws {
        let echo = try await CommandRunner.run("/bin/echo", ["hello"])
        #expect(echo.status == 0)
        #expect(String(data: echo.output, encoding: .utf8) == "hello\n")
        #expect(try await CommandRunner.run("/usr/bin/false", []).status != 0)
        let start = Date()
        let slow = try await CommandRunner.run("/bin/sleep", ["5"], timeout: 0.3)
        #expect(slow.status != 0)
        #expect(Date().timeIntervalSince(start) < 3)
    }

    /// A tool ignoring SIGTERM is killed after the grace time.
    @Test func aToolIgnoringTerminationIsKilled() async throws {
        let start = Date()
        let stubborn = try await CommandRunner.run(
            "/bin/sh",
            ["-c", "trap '' TERM; sleep 10"],
            timeout: 0.2,
            killGrace: 0.3
        )
        #expect(stubborn.status != 0)
        #expect(Date().timeIntervalSince(start) < 5)
    }

    /// A helper that inherited the output and outlives the tool does not hold the call up.
    @Test func anInheritedOutputDoesNotBlock() async throws {
        let start = Date()
        let result = try await CommandRunner.run("/bin/sh", ["-c", "sleep 4 & echo done"])
        #expect(result.status == 0)
        #expect(String(data: result.output, encoding: .utf8) == "done\n")
        #expect(Date().timeIntervalSince(start) < 3)
    }
}

/// The real disk image, signature and Gatekeeper steps against a published release, run by hand:
/// `TRREK_UPDATE_DMG=<path to trrek-vX.Y.Z.dmg> make test` (optionally `TRREK_UNNOTARIZED_APP=<a Developer ID signed,
/// not notarized trrek.app>`). Only temporary folders are written; nothing stays mounted.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["TRREK_UPDATE_DMG"] != nil))
struct UpdateInstallReleaseTests {
    private static let environment = ProcessInfo.processInfo.environment
    private static let old = SemanticVersion(major: 0, minor: 0, patch: 1)

    private static func run(_ tool: String, _ arguments: [String]) async throws -> Int32 {
        try await CommandRunner.run(tool, arguments).status
    }

    /// The image's version, from its file name `trrek-vX.Y.Z.dmg`.
    private static func version(of image: URL) throws -> SemanticVersion {
        let name = image.deletingPathExtension().lastPathComponent
        return try #require(SemanticVersion(String(name.dropFirst("trrek-".count))))
    }

    private static func mountedImages() async throws -> String {
        let info = try await CommandRunner.run("/usr/bin/hdiutil", ["info"])
        return String(data: info.output, encoding: .utf8) ?? ""
    }

    @Test func theReleaseIsStagedVerifiedAndInstalledOverACopy() async throws {
        let image = try URL(fileURLWithPath: #require(Self.environment["TRREK_UPDATE_DMG"]))
        let version = try Self.version(of: image)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("trrek-release-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let installed = try Self.makeInstalledCopy(in: root)

        let installer = UpdateInstaller(bundle: installed)
        let staged = try await installer.prepare(image: image, version: version, current: Self.old)
        let imageQuarantined = getxattr(image.path, "com.apple.quarantine", nil, 0, 0, 0) >= 0
        let stagedQuarantined = Self.quarantinedFiles(in: staged.app).count
        print("image quarantined: \(imageQuarantined), staged files quarantined: \(stagedQuarantined)")
        #expect(try await !Self.mountedImages().contains("trrek-update-"))
        #expect(await CodeSignatureVerifier().verify(staged.app, expected: version, current: version) == .notNewer)

        try await Self.checkTamperedCopies(of: staged.app, version: version, in: root)
        try await Self.checkTamperingAfterPreparing(installer, image: image, version: version)
        try await Self.checkUnsignedImage(installer, version: version, in: root)

        try await installer.install(staged)
        #expect(CodeSignatureVerifier.identity(of: installed).1 == version.description)
        #expect(await CodeSignatureVerifier().verify(installed, expected: version, current: Self.old) == nil)
        let left = try FileManager.default.contentsOfDirectory(atPath: installed.deletingLastPathComponent().path)
        #expect(left == ["trrek.app"])
        #expect(!FileManager.default.fileExists(atPath: staged.folder.path))
        #expect(Self.quarantinedFiles(in: installed).isEmpty)
    }

    /// A staged app re-signed after it was verified is refused right before the swap; the installed app stays.
    private static func checkTamperingAfterPreparing(
        _ installer: UpdateInstaller,
        image: URL,
        version: SemanticVersion
    ) async throws {
        let staged = try await installer.prepare(image: image, version: version, current: old)
        #expect(try await run("/usr/bin/codesign", ["--force", "--sign", "-", staged.app.path]) == 0)
        await #expect(throws: UpdateInstallError.verification(.signature)) {
            try await installer.install(staged)
        }
        #expect(CodeSignatureVerifier.identity(of: installer.bundle).1 == "0.0.1")
        #expect(!FileManager.default.fileExists(atPath: staged.folder.path))
    }

    /// A disk image made from a folder (not signed) is refused before it is attached.
    private static func checkUnsignedImage(
        _ installer: UpdateInstaller,
        version: SemanticVersion,
        in root: URL
    ) async throws {
        let source = root.appendingPathComponent("unsigned-source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let image = root.appendingPathComponent("unsigned.dmg")
        let created = try await run(
            "/usr/sbin/diskutil",
            ["image", "create", "from", "--format", "UDZO", source.path, image.path]
        )
        #expect(created == 0)
        await #expect(throws: UpdateInstallError.verification(.signature)) {
            _ = try await installer.prepare(image: image, version: version, current: old)
        }
    }

    /// A stand-in for the installed app at `root/Applications/trrek.app`, version 0.0.1.
    private static func makeInstalledCopy(in root: URL) throws -> URL {
        let installed = root.appendingPathComponent("Applications/trrek.app")
        let contents = installed.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": AppIdentity.bundleID, "CFBundleShortVersionString": "0.0.1"],
            format: .xml,
            options: 0
        ).write(to: contents.appendingPathComponent("Info.plist"))
        return installed
    }

    /// An ad-hoc re-signed copy and a copy with another version in `Info.plist` fail the signature check; the app
    /// `TRREK_UNNOTARIZED_APP` names fails the notarization check.
    private static func checkTamperedCopies(of app: URL, version: SemanticVersion, in root: URL) async throws {
        let adHoc = root.appendingPathComponent("copies/adhoc/trrek.app")
        let edited = root.appendingPathComponent("copies/edited/trrek.app")
        for copy in [adHoc, edited] {
            #expect(try await run("/usr/bin/ditto", [app.path, copy.path]) == 0)
        }
        #expect(try await run("/usr/bin/codesign", ["--force", "--sign", "-", adHoc.path]) == 0)
        let plist = edited.appendingPathComponent("Contents/Info.plist").path
        #expect(try await run("/usr/bin/plutil", ["-replace", "CFBundleShortVersionString", "-string", "9.9.9", plist])
            == 0)
        let verifier = CodeSignatureVerifier()
        #expect(await verifier.verify(adHoc, expected: version, current: old) == .signature)
        #expect(await verifier.verify(edited, expected: version, current: old) == .signature)
        guard let path = environment["TRREK_UNNOTARIZED_APP"] else { return }
        let local = URL(fileURLWithPath: path)
        let localVersion = try #require(CodeSignatureVerifier.identity(of: local).1.flatMap(SemanticVersion.init))
        let failure = await verifier.verify(local, expected: localVersion, current: old)
        print("not notarized app: \(String(describing: failure))")
        #expect(failure == .notNotarized)
    }

    /// The files in `root` (and `root`) that carry the quarantine attribute.
    private static func quarantinedFiles(in root: URL) -> [String] {
        var paths = [root.path]
        let enumerator = FileManager.default.enumerator(atPath: root.path)
        while let relative = enumerator?.nextObject() as? String {
            paths.append(root.appendingPathComponent(relative).path)
        }
        return paths.filter { getxattr($0, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) >= 0 }
    }
}
