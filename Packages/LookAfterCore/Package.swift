// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LookAfterCore",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .watchOS(.v26)
    ],
    products: [
        .library(name: "LookAfterCore", targets: ["LookAfterCore"])
    ],
    targets: [
        .target(
            name: "LookAfterCore",
            dependencies: [],
            path: "Sources/LookAfterCore",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .testTarget(
            name: "LookAfterCoreTests",
            dependencies: ["LookAfterCore"],
            path: "Tests/LookAfterCoreTests",
            swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .testTarget(
            name: "FlowSchedulingTests",
            dependencies: ["LookAfterCore"],
            path: "Tests/FlowSchedulingTests",
            swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        )
    ]
)
