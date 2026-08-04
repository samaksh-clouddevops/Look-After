// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LookAfterData",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "LookAfterData", targets: ["LookAfterData"])
    ],
    dependencies: [
        .package(path: "../LookAfterCore"),
        .package(path: "../LookAfterAI"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "11.0.0")
    ],
    targets: [
        .target(
            name: "LookAfterData",
            dependencies: [
                "LookAfterCore",
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk")
            ],
            path: "Sources/LookAfterData"
        ),
        .testTarget(
            name: "LookAfterDataTests",
            dependencies: [
                "LookAfterData",
                .product(name: "LookAfterAI", package: "LookAfterAI")
            ],
            path: "Tests/LookAfterDataTests"
        ),
        .testTarget(
            name: "BehaviorMemoryStoreTests",
            dependencies: ["LookAfterData"],
            path: "Tests/BehaviorMemoryStoreTests"
        ),
        .testTarget(
            name: "EnvironmentContextProviderTests",
            dependencies: ["LookAfterData"],
            path: "Tests/EnvironmentContextProviderTests"
        )
    ]
)
