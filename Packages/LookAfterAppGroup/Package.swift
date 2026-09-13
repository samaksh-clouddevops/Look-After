// swift-tools-version: 5.9
import PackageDescription

/// Minimal surface for Widget / App Intent extensions (Phase 8.1).
/// Depends only on Core types already shared via App Group files.
let package = Package(
    name: "LookAfterAppGroup",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "LookAfterAppGroup", targets: ["LookAfterAppGroup"]),
    ],
    dependencies: [
        .package(path: "../LookAfterCore"),
    ],
    targets: [
        .target(
            name: "LookAfterAppGroup",
            dependencies: ["LookAfterCore"],
            path: "Sources/LookAfterAppGroup"
        ),
    ]
)
