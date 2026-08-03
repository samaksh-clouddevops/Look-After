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
        .package(path: "../LookAfterCore")
    ],
    targets: [
        .target(
            name: "ExecutiveBrain",
            dependencies: ["LookAfterCore"],
            path: "Sources/ExecutiveBrain"
        ),
        .testTarget(
            name: "ExecutiveBrainTests",
            dependencies: ["ExecutiveBrain"],
            path: "Tests/ExecutiveBrainTests"
        )
    ]
)
