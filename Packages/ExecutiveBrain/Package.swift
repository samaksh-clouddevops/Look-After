// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ExecutiveBrain",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "ExecutiveBrain", targets: ["ExecutiveBrain"])
    ],
    dependencies: [
        .package(path: "../LookAfterCore")
    ],
    targets: [
        .target(
            name: "ExecutiveBrain",
            dependencies: ["LookAfterCore"],
            path: "Sources/ExecutiveBrain",
            swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .testTarget(
            name: "ExecutiveBrainTests",
            dependencies: ["ExecutiveBrain"],
            path: "Tests/ExecutiveBrainTests",
            swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        )
    ]
)
