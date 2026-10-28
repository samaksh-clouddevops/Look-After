// swift-tools-version: 6.2
import PackageDescription

// A focused integration runner: unrelated legacy test targets cannot prevent the
// month-long task lifecycle checks from compiling and running against production code.
let package = Package(
    name: "TaskSimulation",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../../Packages/LookAfterFeatures"),
        .package(path: "../../Packages/LookAfterCore"),
        .package(path: "../../Packages/LookAfterData"),
        .package(path: "../../Packages/LookAfterAI")
    ],
    targets: [.testTarget(
        name: "TaskSimulationTests",
        dependencies: [
            .product(name: "LookAfterFeatures", package: "LookAfterFeatures"),
            .product(name: "LookAfterCore", package: "LookAfterCore"),
            .product(name: "LookAfterData", package: "LookAfterData"),
            .product(name: "LookAfterAI", package: "LookAfterAI")
        ]
    )]
)
