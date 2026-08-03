// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LookAfterHealth",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "LookAfterHealth", targets: ["LookAfterHealth"])
    ],
    dependencies: [
        .package(path: "../LookAfterCore")
    ],
    targets: [
        .target(
            name: "LookAfterHealth",
            dependencies: ["LookAfterCore"],
            path: "Sources/LookAfterHealth"
        ),
        .testTarget(
            name: "LookAfterHealthTests",
            dependencies: ["LookAfterHealth"],
            path: "Tests/LookAfterHealthTests"
        )
    ]
)
