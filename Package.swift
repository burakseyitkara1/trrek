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
        .executableTarget(
            name: "Trrek",
            dependencies: ["TrrekEngine", "TrrekPlatform"],
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
        )
    ]
)
