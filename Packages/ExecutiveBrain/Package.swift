// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ExecutiveBrain",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "ExecutiveBrain", targets: ["ExecutiveBrain"])
    ],
    dependencies: [
        .package(path: "../LifeOSCore")
    ],
    targets: [
        .target(
            name: "ExecutiveBrain",
            dependencies: ["LifeOSCore"],
            path: "Sources/ExecutiveBrain"
        ),
        .testTarget(
            name: "ExecutiveBrainTests",
            dependencies: ["ExecutiveBrain"],
            path: "Tests/ExecutiveBrainTests"
        )
    ]
)
