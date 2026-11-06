// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "trrek",
    platforms: [.macOS("26.0")],
    targets: [
        .target(
            name: "TrrekEngine",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(name: "CMultitouch"),
        .target(
            name: "TrrekPlatform",
            dependencies: ["TrrekEngine", "CMultitouch"],
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics")
            ]
        ),
        .target(
            name: "TrrekAppCore",
            dependencies: ["TrrekEngine", "TrrekPlatform"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "Trrek",
            dependencies: ["TrrekAppCore", "TrrekEngine", "TrrekPlatform"],
            // The localizations are copied into the app bundle's Resources by scripts/build-app.sh, where
            // `Bundle.main` finds them; SwiftPM does not process them.
            exclude: ["Resources"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "TrrekProbe",
            dependencies: ["TrrekEngine", "TrrekPlatform", "CMultitouch"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TrrekEngineTests",
            dependencies: ["TrrekEngine"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TrrekPlatformTests",
            dependencies: ["TrrekPlatform", "TrrekEngine", "CMultitouch"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TrrekAppCoreTests",
            dependencies: ["TrrekAppCore", "TrrekEngine", "TrrekPlatform"],
            // Read by path (see `UpdateFixtures`), like the localization tables.
            exclude: ["Fixtures"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TrrekAppTests",
            dependencies: ["Trrek", "TrrekAppCore", "TrrekEngine", "TrrekPlatform"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
