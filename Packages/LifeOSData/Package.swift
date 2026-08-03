// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LifeOSData",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "LifeOSData", targets: ["LifeOSData"])
    ],
    dependencies: [
        .package(path: "../LifeOSCore"),
        .package(path: "../LifeOSAI"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "11.0.0")
    ],
    targets: [
        .target(
            name: "LifeOSData",
            dependencies: [
                "LifeOSCore",
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk")
            ],
            path: "Sources/LifeOSData"
        ),
        .testTarget(
            name: "LifeOSDataTests",
            dependencies: [
                "LifeOSData",
                .product(name: "LifeOSAI", package: "LifeOSAI")
            ],
            path: "Tests/LifeOSDataTests"
        ),
        .testTarget(
            name: "BehaviorMemoryStoreTests",
            dependencies: ["LifeOSData"],
            path: "Tests/BehaviorMemoryStoreTests"
        ),
        .testTarget(
            name: "EnvironmentContextProviderTests",
            dependencies: ["LifeOSData"],
            path: "Tests/EnvironmentContextProviderTests"
        )
    ]
)
