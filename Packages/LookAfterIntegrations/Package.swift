// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LookAfterIntegrations",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
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
            path: "Sources/LookAfterIntegrations"
        ),
        .testTarget(
            name: "LookAfterIntegrationsTests",
            dependencies: ["LookAfterIntegrations"],
            path: "Tests/LookAfterIntegrationsTests"
        )
    ]
)
