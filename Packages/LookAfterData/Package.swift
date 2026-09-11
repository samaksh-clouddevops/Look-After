// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LookAfterData",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "LookAfterData", targets: ["LookAfterData"])
    ],
    dependencies: [
        .package(path: "../LookAfterCore"),
        .package(path: "../LookAfterAI"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "11.0.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/google/GoogleSignIn-iOS.git", from: "8.0.0")
    ],
    targets: [
        .target(
            name: "LookAfterData",
            dependencies: [
                "LookAfterCore",
                "LookAfterAI",
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(
                    name: "GoogleSignIn",
                    package: "GoogleSignIn-iOS",
                    condition: .when(platforms: [.iOS])
                )
            ],
            path: "Sources/LookAfterData",
            swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .testTarget(
            name: "LookAfterDataTests",
            dependencies: [
                "LookAfterData",
                .product(name: "LookAfterAI", package: "LookAfterAI")
            ],
            path: "Tests/LookAfterDataTests",
            swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .testTarget(
            name: "BehaviorMemoryStoreTests",
            dependencies: ["LookAfterData"],
            path: "Tests/BehaviorMemoryStoreTests",
            swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .testTarget(
            name: "EnvironmentContextProviderTests",
            dependencies: ["LookAfterData"],
            path: "Tests/EnvironmentContextProviderTests",
            swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        )
    ]
)
