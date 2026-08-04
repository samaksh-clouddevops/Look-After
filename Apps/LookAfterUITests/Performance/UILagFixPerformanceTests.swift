import XCTest

/// End-to-end UI performance scenarios for the ui-lag-fixes branch.
/// Targets align with Documentation/qa/09-performance-benchmarks.md and
/// Documentation/qa/37-ui-lag-fix-scorecard.md.
final class UILagFixPerformanceTests: FlowTestBase {

    // MARK: - Thresholds

    private let tabTargetMs = 200
    private let tabHardFailMs = 1000
    private let taskListOpenTargetMs = 500
    private let taskListOpenHardFailMs = 2000
    private let focusHardFailMs = 500
    private let focusTargetMs = 100
    private let multiTabTargetMs = 1500
    private let multiTabHardFailMs = 4000

    private func perfArgs(extra: [String] = []) -> [String] {
        LaunchArguments.uiTesting(seedFlow: "FLOW-002") + ["-SkipLiveActivity"] + extra
    }

    // MARK: - Tab transitions (batch publish / shell)

    func testBriefingToTodayTabWithinBudget() throws {
        let source = QASource("PERF-LAG-TAB-TODAY", document: "Documentation/qa/37-ui-lag-fix-scorecard.md")
        app.launchArguments = perfArgs()
        app.launch()
        waitForBriefing(timeout: 20)

        let start = Date()
        tapTab("today")
        let visible = app.otherElements["screen-today"].waitForExistence(timeout: 5)
        let ms = Int(Date().timeIntervalSince(start) * 1000)

        write(source, ms: ms, pass: visible && ms < tabHardFailMs, metrics: ["tabTodayMs": Double(ms)], logs: [
            "visible=\(visible)"
        ], target: Double(tabTargetMs), hardFail: Double(tabHardFailMs))
        XCTAssertTrue(visible, "Today screen should appear")
        XCTAssertLessThan(ms, tabHardFailMs, "Tab to Today took \(ms)ms")
    }

    func testTodayToBriefingTabWithinBudget() throws {
        let source = QASource("PERF-LAG-TAB-BRIEFING", document: "Documentation/qa/37-ui-lag-fix-scorecard.md")
        app.launchArguments = perfArgs()
        app.launch()
        waitForBriefing(timeout: 20)
        tapTab("today")
        _ = app.otherElements["screen-today"].waitForExistence(timeout: 8)

        let start = Date()
        tapTab("briefing")
        let visible = app.otherElements["screen-briefing"].waitForExistence(timeout: 5)
            || app.buttons["tab-briefing"].waitForExistence(timeout: 2)
        let ms = Int(Date().timeIntervalSince(start) * 1000)

        write(source, ms: ms, pass: visible && ms < tabHardFailMs, metrics: ["tabBriefingMs": Double(ms)],
              target: Double(tabTargetMs), hardFail: Double(tabHardFailMs))
        XCTAssertTrue(visible)
        XCTAssertLessThan(ms, tabHardFailMs, "Tab to Briefing took \(ms)ms")
    }

    // MARK: - Task list open (filter memoization path)

    func testTaskListOpensWithinBudget() throws {
        let source = QASource("PERF-LAG-TASK-LIST-OPEN", document: "Documentation/qa/37-ui-lag-fix-scorecard.md")
        app.launchArguments = perfArgs()
        app.launch()
        waitForBriefing(timeout: 20)

        let start = Date()
        tapTab("today")
        if app.buttons["nav-all-tasks"].waitForExistence(timeout: 4) {
            app.buttons["nav-all-tasks"].tap()
        }
        let listVisible = app.otherElements["screen-task-list"].waitForExistence(timeout: 6)
        let ms = Int(Date().timeIntervalSince(start) * 1000)

        write(source, ms: ms, pass: listVisible && ms < taskListOpenHardFailMs, metrics: [
            "taskListOpenMs": Double(ms)
        ], target: Double(taskListOpenTargetMs), hardFail: Double(taskListOpenHardFailMs))
        XCTAssertTrue(listVisible, "Task list should appear")
        XCTAssertLessThan(ms, taskListOpenHardFailMs, "Task list open took \(ms)ms")
    }

    // MARK: - Focus timer (Live Activity deferred)

    func testFocusStartFromSeededTimelineWithinBudget() throws {
        let source = QASource("PERF-LAG-FOCUS-START", document: "Documentation/qa/37-ui-lag-fix-scorecard.md")
        app.launchArguments = perfArgs(extra: ["-SeedFocusTask"])
        app.launch()
        waitForBriefing(timeout: 20)
        tapTab("today")
        XCTAssertTrue(app.otherElements["screen-today"].waitForExistence(timeout: 10))

        let card = app.otherElements["timeline-event-card-uitest-focus-task"]
        guard card.waitForExistence(timeout: 20) else {
            write(source, ms: -1, pass: false, logs: ["seeded-focus-card-missing"])
            throw XCTSkip("Seeded focus task not available in this configuration")
        }
        card.tap()
        XCTAssertTrue(app.buttons["focus-start-now"].waitForExistence(timeout: 4))

        let start = Date()
        app.buttons["focus-start-now"].tap()
        let screen = app.otherElements["screen-focus-session"].waitForExistence(timeout: 3)
        let timer = app.staticTexts["focus-timer-remaining"].waitForExistence(timeout: 3)
        let ms = Int(Date().timeIntervalSince(start) * 1000)

        write(source, ms: ms, pass: screen && timer && ms < focusHardFailMs, metrics: [
            "focusStartMs": Double(ms)
        ], logs: ["screen=\(screen)", "timer=\(timer)"],
              target: Double(focusTargetMs), hardFail: Double(focusHardFailMs))
        XCTAssertTrue(screen && timer)
        XCTAssertLessThan(ms, focusHardFailMs, "Focus start took \(ms)ms")
    }

    func testFocusStopDismissesWithinBudget() throws {
        let source = QASource("PERF-LAG-FOCUS-STOP", document: "Documentation/qa/37-ui-lag-fix-scorecard.md")
        app.launchArguments = perfArgs(extra: ["-AutoStartFocusSession"])
        app.launch()
        XCTAssertTrue(app.otherElements["screen-focus-session"].waitForExistence(timeout: 20))

        let stop = app.buttons["focus-session-stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))

        let start = Date()
        stop.tap()
        let dismissed = !app.otherElements["screen-focus-session"].waitForExistence(timeout: 2)
            || app.otherElements["screen-root"].waitForExistence(timeout: 2)
        let gone = !app.otherElements["screen-focus-session"].exists
        let ms = Int(Date().timeIntervalSince(start) * 1000)

        write(source, ms: ms, pass: gone && ms < focusHardFailMs, metrics: ["focusStopMs": Double(ms)], logs: [
            "dismissed=\(dismissed)", "gone=\(gone)"
        ], target: Double(focusTargetMs), hardFail: Double(focusHardFailMs))
        XCTAssertTrue(gone, "Focus overlay should dismiss")
        XCTAssertLessThan(ms, focusHardFailMs, "Focus stop took \(ms)ms")
    }

    // MARK: - Multi-tab sweep (steady shell)

    func testMultiTabSweepWithinBudget() throws {
        let source = QASource("PERF-LAG-MULTI-TAB", document: "Documentation/qa/37-ui-lag-fix-scorecard.md")
        app.launchArguments = perfArgs()
        app.launch()
        waitForBriefing(timeout: 20)

        let tabs = ["today", "briefing", "today", "briefing"]
        let start = Date()
        for tab in tabs {
            tapTab(tab)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        let ms = Int(Date().timeIntervalSince(start) * 1000)

        write(source, ms: ms, pass: ms < multiTabHardFailMs, metrics: ["multiTabSweepMs": Double(ms)], logs: [
            "tabs=\(tabs.count)"
        ], target: Double(multiTabTargetMs), hardFail: Double(multiTabHardFailMs))
        XCTAssertLessThan(ms, multiTabHardFailMs, "Multi-tab sweep took \(ms)ms")
    }

    // MARK: - Helpers

    /// Score 0–100: 100 at target, 70 at hard-fail boundary, 0 at 2× hard fail.
    private func score(ms: Double, target: Double, hardFail: Double) -> Double {
        if ms < 0 { return 0 }
        if ms <= target { return 100 }
        if ms >= hardFail * 2 { return 0 }
        if ms >= hardFail {
            let over = ms - hardFail
            return max(0, 69 * (1 - over / hardFail))
        }
        let ratio = (ms - target) / (hardFail - target)
        return 100 - (30 * ratio)
    }

    private func write(
        _ source: QASource,
        ms: Int,
        pass: Bool,
        metrics: [String: Double] = [:],
        logs: [String] = [],
        target: Double? = nil,
        hardFail: Double? = nil
    ) {
        var allMetrics = metrics
        var allLogs = logs
        if let target, let hardFail, ms >= 0 {
            let s = score(ms: Double(ms), target: target, hardFail: hardFail)
            allMetrics["score"] = s
            allLogs.append(String(format: "score=%.1f accept=%@", s, s >= 70 ? "true" : "false"))
        }
        EvidenceWriter.write(
            source: source,
            status: pass ? "pass" : "fail",
            durationMs: max(ms, 0),
            logs: allLogs,
            metrics: allMetrics
        )
    }
}
