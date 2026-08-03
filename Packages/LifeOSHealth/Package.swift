// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LifeOSHealth",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "LifeOSHealth", targets: ["LifeOSHealth"])
    ],
    dependencies: [
        .package(path: "../LifeOSCore")
    ],
    targets: [
        .target(
            name: "LifeOSHealth",
            dependencies: ["LifeOSCore"],
            path: "Sources/LifeOSHealth"
        ),
        .testTarget(
            name: "LifeOSHealthTests",
            dependencies: ["LifeOSHealth"],
            path: "Tests/LifeOSHealthTests"
        )
    ]
)
