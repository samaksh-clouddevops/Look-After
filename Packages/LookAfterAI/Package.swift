// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LookAfterAI",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
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
            path: "Sources/LookAfterAI"
        ),
        .testTarget(
            name: "LookAfterAITests",
            dependencies: ["LookAfterAI"],
            path: "Tests/LookAfterAITests"
        ),
        .testTarget(
            name: "FlowDirectorTests",
            dependencies: ["LookAfterAI"],
            path: "Tests/FlowDirectorTests"
        )
    ]
)
