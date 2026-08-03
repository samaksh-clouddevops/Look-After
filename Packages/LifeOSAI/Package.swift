// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LifeOSAI",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "LifeOSAI", targets: ["LifeOSAI"])
    ],
    dependencies: [
        .package(path: "../LifeOSCore")
    ],
    targets: [
        .target(
            name: "LifeOSAI",
            dependencies: ["LifeOSCore"],
            path: "Sources/LifeOSAI"
        ),
        .testTarget(
            name: "LifeOSAITests",
            dependencies: ["LifeOSAI"],
            path: "Tests/LifeOSAITests"
        ),
        .testTarget(
            name: "FlowDirectorTests",
            dependencies: ["LifeOSAI"],
            path: "Tests/FlowDirectorTests"
        )
    ]
)
