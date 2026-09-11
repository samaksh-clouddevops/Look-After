// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LookAfterFeatures",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "LookAfterFeatures", targets: ["LookAfterFeatures"])
    ],
    dependencies: [
        .package(path: "../LookAfterCore"),
        .package(path: "../LookAfterAI"),
        .package(path: "../LookAfterData"),
        .package(path: "../ExecutiveBrain"),
        .package(path: "../LookAfterIntegrations")
    ],
    targets: [
        .target(
            name: "LookAfterFeatures",
            dependencies: ["LookAfterCore", "LookAfterAI", "LookAfterData", "ExecutiveBrain", "LookAfterIntegrations"],
            path: "Sources/LookAfterFeatures",
            swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("NonisolatedNonsendingByDefault"), .defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "LookAfterFeaturesTests",
            dependencies: ["LookAfterFeatures"],
            path: "Tests/LookAfterFeaturesTests",
            swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        )
    ]
)
