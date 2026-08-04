// swift-tools-version: 5.9
import PackageDescription

/// Linux/Docker harness for pure guided-tour geometry (no SwiftUI).
/// Sources under Sources/TourPlacement are a mirror of
/// Packages/LookAfterCore/Sources/LookAfterCore/Tour — keep in sync when changing the engine.
let package = Package(
    name: "TourPlacementHarness",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "TourPlacement", targets: ["TourPlacement"])
    ],
    targets: [
        .target(
            name: "TourPlacement",
            path: "Sources/TourPlacement"
        ),
        .testTarget(
            name: "TourPlacementTests",
            dependencies: ["TourPlacement"],
            path: "Tests/TourPlacementTests"
        )
    ]
)
