// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LookAfterHealth",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
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
            path: "Sources/LookAfterHealth",
            swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .testTarget(
            name: "LookAfterHealthTests",
            dependencies: ["LookAfterHealth"],
            path: "Tests/LookAfterHealthTests",
            swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        )
    ]
)
