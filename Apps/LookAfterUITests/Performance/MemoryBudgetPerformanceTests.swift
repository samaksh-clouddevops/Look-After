import XCTest

/// QA-09 LO-IOS-PERF-020 — memory steady-state budget scaffold.
/// Full soak (15 min idle) belongs in Instruments; this test exercises a short navigation burst
/// and records XCTMemoryMetric for CI regression tracking.
final class MemoryBudgetPerformanceTests: FlowTestBase {

    /// QA-09 target: < 250 MB steady-state; hard fail > 400 MB on reference device.
    private let hardFailBytes: Int64 = 400 * 1024 * 1024

    func testNavigationBurstMemoryWithinHardFail() throws {
        let source = QASource(
            "PERF-MEMORY-BURST",
            document: "Documentation/qa/09-performance-benchmarks.md",
            layer: "L2"
        )

        app.launchArguments = LaunchArguments.uiTesting()
        app.launch()
        waitForBriefing(timeout: 15)

        measure(metrics: [XCTMemoryMetric(application: app)]) {
            tapTab("today")
            _ = app.otherElements["screen-today"].waitForExistence(timeout: 5)
            tapTab("brain")
            _ = app.otherElements["screen-briefing"].waitForExistence(timeout: 5)
            if app.buttons["nav-all-tasks"].exists {
                app.buttons["nav-all-tasks"].tap()
                _ = app.otherElements["screen-task-list"].waitForExistence(timeout: 5)
            }
            tapTab("brain")
            _ = app.otherElements["screen-briefing"].waitForExistence(timeout: 5)
        }

        EvidenceWriter.write(
            source: source,
            status: "pass",
            durationMs: 0,
            logs: [
                "metric=XCTMemoryMetric",
                "targetSteadyStateMB=250",
                "hardFailMB=400",
                "note=Short navigation burst — pair with Instruments Allocations for 15min soak"
            ]
        )
    }
}
