// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ExecutiveValidationPlatform",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "EVPCore", targets: ["EVPCore"]),
        .executable(name: "evp", targets: ["evp"])
    ],
    dependencies: [
        .package(path: "../../Packages/ExecutiveBrain"),
        .package(path: "../../Packages/LookAfterCore")
    ],
    targets: [
        .target(
            name: "EVPCore",
            dependencies: [
                .product(name: "ExecutiveBrain", package: "ExecutiveBrain"),
                .product(name: "LookAfterCore", package: "LookAfterCore")
            ],
            path: "Sources/EVPCore",
            swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .executableTarget(
            name: "evp",
            dependencies: ["EVPCore"],
            path: "Sources/evp",
            swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .testTarget(
            name: "EVPTests",
            dependencies: ["EVPCore"],
            path: "Tests/EVPTests",
            swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        )
    ]
)
