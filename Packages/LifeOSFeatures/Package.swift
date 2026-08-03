// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LifeOSFeatures",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "LifeOSFeatures", targets: ["LifeOSFeatures"])
    ],
    dependencies: [
        .package(path: "../LifeOSCore"),
        .package(path: "../LifeOSAI"),
        .package(path: "../LifeOSData"),
        .package(path: "../ExecutiveBrain")
    ],
    targets: [
        .target(
            name: "LifeOSFeatures",
            dependencies: ["LifeOSCore", "LifeOSAI", "LifeOSData", "ExecutiveBrain"],
            path: "Sources/LifeOSFeatures"
        ),
        .testTarget(
            name: "LifeOSFeaturesTests",
            dependencies: ["LifeOSFeatures"],
            path: "Tests/LifeOSFeaturesTests"
        )
    ]
)
