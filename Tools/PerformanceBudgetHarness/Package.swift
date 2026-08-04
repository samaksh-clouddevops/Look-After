// swift-tools-version: 5.9
import PackageDescription

/// Minimal Linux/Windows-Docker runnable harness for PerformanceBudgets scorecard logic.
/// Full LookAfterCore cannot build without SwiftUI (Apple platforms only).
let package = Package(
    name: "PerformanceBudgetHarness",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "PerfBudgets", targets: ["PerfBudgets"])
    ],
    targets: [
        .target(
            name: "PerfBudgets",
            path: "Sources/PerfBudgets"
        ),
        .testTarget(
            name: "PerfBudgetsTests",
            dependencies: ["PerfBudgets"],
            path: "Tests/PerfBudgetsTests"
        )
    ]
)
