// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LookAfterIntegrations",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "LookAfterIntegrations", targets: ["LookAfterIntegrations"])
    ],
    dependencies: [
        .package(path: "../LookAfterCore"),
        .package(path: "../LookAfterAI"),
        .package(path: "../LookAfterData")
    ],
    targets: [
        .target(
            name: "LookAfterIntegrations",
            dependencies: ["LookAfterCore", "LookAfterAI", "LookAfterData"],
            path: "Sources/LookAfterIntegrations",
            swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .testTarget(
            name: "LookAfterIntegrationsTests",
            dependencies: ["LookAfterIntegrations"],
            path: "Tests/LookAfterIntegrationsTests",
            swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        )
    ]
)
