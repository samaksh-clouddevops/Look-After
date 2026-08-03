// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ExecutiveValidationPlatform",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EVPCore", targets: ["EVPCore"]),
        .executable(name: "evp", targets: ["evp"])
    ],
    dependencies: [
        .package(path: "../../Packages/ExecutiveBrain"),
        .package(path: "../../Packages/LifeOSCore")
    ],
    targets: [
        .target(
            name: "EVPCore",
            dependencies: [
                .product(name: "ExecutiveBrain", package: "ExecutiveBrain"),
                .product(name: "LifeOSCore", package: "LifeOSCore")
            ],
            path: "Sources/EVPCore"
        ),
        .executableTarget(
            name: "evp",
            dependencies: ["EVPCore"],
            path: "Sources/evp"
        ),
        .testTarget(
            name: "EVPTests",
            dependencies: ["EVPCore"],
            path: "Tests/EVPTests"
        )
    ]
)
