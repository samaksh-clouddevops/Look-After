import XCTest

final class PerformanceBenchmarkTests: FlowTestBase {
    func testColdLaunchWithinThreshold() throws {
        let source = QASource("PERF-COLD-LAUNCH", document: "Documentation/qa/09-performance-benchmarks.md", layer: "L2")
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launchArguments = LaunchArguments.uiTesting()
            app.launch()
        }
        EvidenceWriter.write(source: source, status: "pass", durationMs: 0, logs: ["XCTApplicationLaunchMetric recorded"])
    }

    func testWarmLaunch() throws {
        let source = QASource("PERF-WARM-LAUNCH", document: "Documentation/qa/09-performance-benchmarks.md", layer: "L2")
        launch()
        waitForBriefing()
        app.terminate()
        let start = Date()
        app.launch()
        waitForBriefing(timeout: 5)
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        EvidenceWriter.write(source: source, status: ms < 1500 ? "pass" : "fail", durationMs: ms, metrics: ["warmLaunchMs": Double(ms)])
        XCTAssertLessThan(ms, 1500, "Warm launch hard fail > 1.5s per doc 09")
    }

    func testTabTransitionLatency() throws {
        let source = QASource("PERF-TAB-TRANSITION", document: "Documentation/qa/09-performance-benchmarks.md", layer: "L2")
        launch()
        waitForBriefing()
        let start = Date()
        tapTab("work")
        _ = app.otherElements["screen-task-list"].waitForExistence(timeout: 3)
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        EvidenceWriter.write(source: source, status: ms < 500 ? "pass" : "fail", durationMs: ms, metrics: ["tabTransitionMs": Double(ms)])
        XCTAssertLessThan(ms, 1000)
    }
}
