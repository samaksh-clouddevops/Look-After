// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LifeOSCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "LifeOSCore", targets: ["LifeOSCore"])
    ],
    targets: [
        .target(
            name: "LifeOSCore",
            dependencies: [],
            path: "Sources/LifeOSCore"
        ),
        .testTarget(
            name: "LifeOSCoreTests",
            dependencies: ["LifeOSCore"],
            path: "Tests/LifeOSCoreTests"
        ),
        .testTarget(
            name: "FlowSchedulingTests",
            dependencies: ["LifeOSCore"],
            path: "Tests/FlowSchedulingTests"
        )
    ]
)
