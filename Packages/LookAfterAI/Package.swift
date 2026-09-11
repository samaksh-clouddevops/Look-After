// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LookAfterAI",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "LookAfterAI", targets: ["LookAfterAI"])
    ],
    dependencies: [
        .package(path: "../LookAfterCore")
    ],
    targets: [
        .target(
            name: "LookAfterAI",
            dependencies: ["LookAfterCore"],
            path: "Sources/LookAfterAI",
            swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .testTarget(
            name: "LookAfterAITests",
            dependencies: ["LookAfterAI"],
            path: "Tests/LookAfterAITests",
            swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .testTarget(
            name: "FlowDirectorTests",
            dependencies: ["LookAfterAI"],
            path: "Tests/FlowDirectorTests",
            swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        )
    ]
)
