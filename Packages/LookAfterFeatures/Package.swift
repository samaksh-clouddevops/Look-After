// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LookAfterFeatures",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "LookAfterFeatures", targets: ["LookAfterFeatures"])
    ],
    dependencies: [
        .package(path: "../LookAfterCore"),
        .package(path: "../LookAfterAI"),
        .package(path: "../LookAfterData"),
        .package(path: "../ExecutiveBrain")
    ],
    targets: [
        .target(
            name: "LookAfterFeatures",
            dependencies: ["LookAfterCore", "LookAfterAI", "LookAfterData", "ExecutiveBrain"],
            path: "Sources/LookAfterFeatures"
        ),
        .testTarget(
            name: "LookAfterFeaturesTests",
            dependencies: ["LookAfterFeatures"],
            path: "Tests/LookAfterFeaturesTests"
        )
    ]
)
