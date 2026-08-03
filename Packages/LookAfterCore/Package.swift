// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LookAfterCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "LookAfterCore", targets: ["LookAfterCore"])
    ],
    targets: [
        .target(
            name: "LookAfterCore",
            dependencies: [],
            path: "Sources/LookAfterCore"
        ),
        .testTarget(
            name: "LookAfterCoreTests",
            dependencies: ["LookAfterCore"],
            path: "Tests/LookAfterCoreTests"
        ),
        .testTarget(
            name: "FlowSchedulingTests",
            dependencies: ["LookAfterCore"],
            path: "Tests/FlowSchedulingTests"
        )
    ]
)
