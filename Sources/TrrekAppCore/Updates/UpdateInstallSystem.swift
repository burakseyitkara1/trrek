import DiskArbitration
import Foundation
import Security
import TrrekPlatform

// MARK: - Disk image

/// Why the app could not be copied out of the disk image.
enum DiskImageError: Error, Equatable {
    case attach
    case noApp
    case copy(Int32)
}

/// Checks the image's Developer ID signature, attaches it with `diskutil image attach` (read-only, hidden from
/// Finder, at a private mount point), falls back to `hdiutil attach` when that fails, copies `trrek.app` with `ditto`
/// and ejects the image on every path.
public struct DiskImageAppExtractor: DiskImageAppExtracting {
    public static let appName = "trrek.app"
    /// The prefix of the mount point folders in the temporary folder.
    static let mountPrefix = "trrek-update-"

    private let temporaryFolder: URL

    public init(temporaryFolder: URL = FileManager.default.temporaryDirectory) {
        self.temporaryFolder = temporaryFolder
    }

    public func extractApp(from image: URL, into folder: URL) async throws -> URL {
        // The file system in the image is parsed only once the image is known to come from the release team.
        let signed = try await runOffMain {
            ReleaseSigner.satisfies(image, ReleaseSigner.developerID, label: "disk-image-signature")
        }
        guard signed else { throw UpdateVerificationFailure.signature }
        let mountPoint = temporaryFolder.appendingPathComponent(Self.mountPrefix + UUID().uuidString)
        let device = try await Self.attach(image, at: mountPoint)
        do {
            let app = try await Self.copyApp(from: mountPoint, into: folder)
            await Self.detach(device, mountPoint: mountPoint)
            return app
        } catch {
            await Self.detach(device, mountPoint: mountPoint)
            throw error
        }
    }

    /// The attach commands in the order tried; both print a property list naming the attached devices.
    static func attachCommands(image: String, mountPoint: String) -> [(String, [String])] {
        [
            (
                "/usr/sbin/diskutil",
                ["image", "attach", "--plist", "--readOnly", "--nobrowse", "--mountPoint", mountPoint, image]
            ),
            (
                "/usr/bin/hdiutil",
                ["attach", "-plist", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mountPoint, image]
            )
        ]
    }

    /// Attaches `image` at `mountPoint` and returns what to eject: the image's whole disk, or the mount point when
    /// the output names none.
    static func attach(_ image: URL, at mountPoint: URL) async throws -> String {
        for (tool, arguments) in attachCommands(image: image.path, mountPoint: mountPoint.path) {
            do {
                let result = try await CommandRunner.run(tool, arguments)
                if result.status == 0 {
                    return wholeDisk(inAttachOutput: result.output) ?? mountPoint.path
                }
                appLogger.error("\(tool, privacy: .public) attach exited with \(result.status, privacy: .public)")
            } catch {
                appLogger.error("\(tool) attach failed", error)
            }
            // A tool stopped after it attached (its timeout) leaves the image mounted without naming its device.
            await release(mountPoint)
        }
        throw DiskImageError.attach
    }

    /// Ejects whatever is mounted at `mountPoint`, or removes the folder when it is empty and nothing is mounted.
    static func release(_ mountPoint: URL) async {
        if isMountPoint(mountPoint) {
            await detach(mountPoint.path, mountPoint: mountPoint)
        } else {
            // Only an empty folder is removed, never a mounted volume.
            rmdir(mountPoint.path)
        }
    }

    /// Whether a volume is mounted at `url`: it lies on another device than its parent folder.
    static func isMountPoint(_ url: URL) -> Bool {
        var own = stat()
        var parent = stat()
        guard lstat(url.path, &own) == 0, lstat(url.deletingLastPathComponent().path, &parent) == 0 else {
            return false
        }
        return own.st_dev != parent.st_dev
    }

    /// Ejects images a run that was interrupted (trrek quit or crashed while installing) left at
    /// `trrek-update-*` mount points, and removes those folders.
    public func cleanUpLeftovers() async {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: temporaryFolder.path)) ?? []
        for name in names where name.hasPrefix(Self.mountPrefix) {
            appLogger.notice("removing the leftover update mount point \(name, privacy: .public)")
            await Self.release(temporaryFolder.appendingPathComponent(name))
        }
    }

    /// The whole disk (`disk8` or `/dev/disk8`) among the `system-entities` of an attach property list.
    static func wholeDisk(inAttachOutput data: Data) -> String? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]]
        else { return nil }
        return entities.compactMap { $0["dev-entry"] as? String }.first { entry in
            let name = entry.hasPrefix("/dev/") ? entry.dropFirst(5) : Substring(entry)
            return name.hasPrefix("disk") && name.dropFirst(4).allSatisfy(\.isNumber) && name.count > 4
        }
    }

    /// Copies `volume/trrek.app` into `folder`; refuses a link or a file in its place.
    static func copyApp(from volume: URL, into folder: URL) async throws -> URL {
        let source = volume.appendingPathComponent(appName)
        let values = try? source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isDirectory == true, values?.isSymbolicLink != true else { throw DiskImageError.noApp }
        let destination = folder.appendingPathComponent(appName)
        let result = try await CommandRunner.run("/usr/bin/ditto", [source.path, destination.path])
        guard result.status == 0 else { throw DiskImageError.copy(result.status) }
        return destination
    }

    /// Ejects `device` with `diskutil eject`, then with `hdiutil detach -force` if that fails, and removes the mount
    /// point folder if it is left empty.
    static func detach(_ device: String, mountPoint: URL) async {
        let commands = [
            ("/usr/sbin/diskutil", ["eject", device]),
            ("/usr/bin/hdiutil", ["detach", device, "-force"])
        ]
        for (tool, arguments) in commands {
            if let result = try? await CommandRunner.run(tool, arguments), result.status == 0 {
                break
            }
            appLogger.error("\(tool, privacy: .public) could not detach the update disk image")
        }
        rmdir(mountPoint.path)
    }
}

// MARK: - Verification

/// Checks the staged app's code signature against trrek's Developer ID requirement, its `Info.plist` identity and
/// version, and Gatekeeper's assessment (notarization).
public struct CodeSignatureVerifier: UpdateVerifying {
    /// trrek's bundle identifier, signed with a Developer ID Application certificate of the release team.
    public static let requirement = #"identifier "com.burakseyitkara.trrek" and "# + ReleaseSigner.developerID

    public init() {}

    public func verify(
        _ app: URL,
        expected: SemanticVersion,
        current: SemanticVersion
    ) async -> UpdateVerificationFailure? {
        do {
            if let failure = try await runOffMain({ Self.checkSignatureAndIdentity(app, expected, current) }) {
                return failure
            }
        } catch {
            // The work does not throw; were it to, nothing was checked.
            return .signature
        }
        let notarized = try? await runOffMain {
            ReleaseSigner.satisfies(app, "notarized", label: "notarization")
        }
        guard notarized == true else { return .notNotarized }
        // A second opinion; on its own it would pass anything while Gatekeeper is turned off.
        return await Self.isAcceptedByGatekeeper(app) ? nil : .notNotarized
    }

    /// The signature check, then the `Info.plist` values it seals; `.none` when both pass.
    private static func checkSignatureAndIdentity(
        _ app: URL,
        _ expected: SemanticVersion,
        _ current: SemanticVersion
    ) -> UpdateVerificationFailure? {
        guard hasValidSignature(app) else { return .signature }
        let (bundleID, version) = identity(of: app)
        return UpdateInstallPolicy.identityProblem(
            bundleID: bundleID,
            version: version,
            expected: expected,
            current: current
        )
    }

    /// The signature of every architecture and nested code is valid, strictly, and meets `requirement`.
    static func hasValidSignature(_ app: URL) -> Bool {
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        return ReleaseSigner.satisfies(app, requirement, flags: flags, label: "signature")
    }

    /// `CFBundleIdentifier` and `CFBundleShortVersionString` from the app's `Info.plist`.
    static func identity(of app: URL) -> (String?, String?) {
        let file = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: file),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return (nil, nil) }
        return (plist["CFBundleIdentifier"] as? String, plist["CFBundleShortVersionString"] as? String)
    }

    /// `spctl --assess --type execute` accepts the app (notarized Developer ID).
    static func isAcceptedByGatekeeper(_ app: URL) async -> Bool {
        do {
            let result = try await CommandRunner.run("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path])
            if result.status != 0 {
                appLogger.error("update assessment refused: \(result.status, privacy: .public)")
            }
            return result.status == 0
        } catch {
            appLogger.error("update assessment failed", error)
            return false
        }
    }
}

// MARK: - Replacement

/// Removes the quarantine attribute from the staged app (its signature and notarization are checked by trrek, so the
/// first-launch prompt adds nothing) and swaps it into place with `FileManager.replaceItemAt`, keeping the previous
/// app as a hidden backup next to the bundle until the installed app passed verification.
public struct BundleReplacer: BundleReplacing {
    /// The backup's name next to the bundle: hidden, and without the `.app` extension so the system never registers
    /// it as an app.
    public static let backupName = ".trrek-previous"
    /// The error's user info key `replaceItemAt` uses for where it left the original item after a failure.
    static let originalItemLocationKey = "NSFileOriginalItemLocationKey"

    public init() {}

    public static func backup(for bundle: URL) -> URL {
        bundle.deletingLastPathComponent().appendingPathComponent(backupName)
    }

    public func removeQuarantine(in staged: URL) async {
        _ = try? await runOffMain { Self.removeQuarantine(in: staged) }
    }

    public func swap(_ bundle: URL, with staged: URL) async throws -> URL {
        try await runOffMain {
            let backup = Self.backup(for: bundle)
            Self.removeStaleBackup(next: bundle)
            do {
                _ = try FileManager.default.replaceItemAt(
                    bundle,
                    withItemAt: staged,
                    backupItemName: Self.backupName,
                    options: [.usingNewMetadataOnly, .withoutDeletingBackupItem]
                )
            } catch {
                Self.recover(bundle, after: error)
                throw error
            }
            return backup
        }
    }

    public func restore(_ bundle: URL, from backup: URL) async throws {
        try await runOffMain {
            _ = try FileManager.default.replaceItemAt(
                bundle,
                withItemAt: backup,
                backupItemName: nil,
                options: .usingNewMetadataOnly
            )
        }
    }

    public func removeBackup(next bundle: URL) async {
        _ = try? await runOffMain { Self.removeStaleBackup(next: bundle) }
    }

    /// Removes a backup left next to `bundle` by an earlier install that was interrupted.
    static func removeStaleBackup(next bundle: URL) {
        let backup = backup(for: bundle)
        guard backup.standardizedFileURL.path != bundle.standardizedFileURL.path,
              FileManager.default.fileExists(atPath: backup.path)
        else { return }
        do {
            try FileManager.default.removeItem(at: backup)
        } catch {
            appLogger.error("update backup cleanup failed", error)
        }
    }

    /// After a failed swap, puts the previous app back at `bundle` when it is no longer there: from where
    /// `replaceItemAt` reported leaving it, else from the backup.
    static func recover(_ bundle: URL, after error: any Error) {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: bundle.path) else { return }
        let reported = (error as NSError).userInfo[originalItemLocationKey] as? URL
        for candidate in [reported, backup(for: bundle)].compactMap(\.self) {
            guard manager.fileExists(atPath: candidate.path) else { continue }
            do {
                try manager.moveItem(at: candidate, to: bundle)
                appLogger.notice("update swap failed; the previous app was put back")
                return
            } catch {
                appLogger.error("update rollback from a candidate failed", error)
            }
        }
        appLogger.fault("update swap failed and the previous app could not be put back")
    }

    /// Removes `com.apple.quarantine` from `root` and everything inside it, without following links.
    static func removeQuarantine(in root: URL) {
        var paths = [root.path]
        if let enumerator = FileManager.default.enumerator(atPath: root.path) {
            while let relative = enumerator.nextObject() as? String {
                paths.append(root.appendingPathComponent(relative).path)
            }
        }
        for path in paths {
            removexattr(path, "com.apple.quarantine", XATTR_NOFOLLOW)
        }
    }
}

// MARK: - Location

/// Reads the bundle's location from the file system; a disk image is recognized by its device model.
public struct SystemInstallLocation: InstallLocationInspecting {
    /// The device model DiskArbitration reports for an attached disk image.
    static let diskImageModel = "Disk Image"

    public init() {}

    public func facts(for bundle: URL) -> InstallLocationFacts {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        let exists = manager.fileExists(atPath: bundle.path, isDirectory: &isDirectory)
        let hasInfo = manager.fileExists(atPath: bundle.appendingPathComponent("Contents/Info.plist").path)
        let values = try? bundle.resourceValues(forKeys: [.volumeIsReadOnlyKey, .volumeURLKey])
        let writable = manager.isWritableFile(atPath: bundle.path)
            && manager.isWritableFile(atPath: bundle.deletingLastPathComponent().path)
        return InstallLocationFacts(
            isAppBundle: bundle.pathExtension == "app" && exists && isDirectory.boolValue && hasInfo,
            path: bundle.path,
            isOnDiskImage: values?.volume.map(Self.isDiskImage) ?? false,
            isOnReadOnlyVolume: values?.volumeIsReadOnly ?? false,
            isWritable: writable
        )
    }

    static func isDiskImage(_ volume: URL) -> Bool {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, volume as CFURL),
              let description = DADiskCopyDescription(disk) as? [String: Any]
        else { return false }
        return description[kDADiskDescriptionDeviceModelKey as String] as? String == diskImageModel
    }
}
