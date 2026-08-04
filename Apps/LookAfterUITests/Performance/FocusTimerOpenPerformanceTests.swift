import XCTest

/// Measures how quickly the focus timer UI appears after the user starts a session.
/// Targets are aligned with Documentation/qa/09-performance-benchmarks.md.
final class FocusTimerOpenPerformanceTests: FlowTestBase {

    /// Perceived instant — one frame budget at 60fps.
    private let targetMs = 100
    /// Hard fail for tap → timer visible on reference simulator.
    private let hardFailMs = 500

    private func perfLaunchArgs(extra: [String] = []) -> [String] {
        LaunchArguments.uiTesting(seedFlow: "FLOW-002") + ["-SkipLiveActivity"] + extra
    }

    // MARK: - Auto-start (overlay paint after shell is ready)

    func testFocusTimerOverlayAppearsQuicklyOnAutoStart() throws {
        let source = QASource(
            "PERF-FOCUS-TIMER-AUTO",
            document: "Documentation/qa/09-performance-benchmarks.md",
            layer: "L2"
        )

        app.launchArguments = perfLaunchArgs(extra: ["-AutoStartFocusSession"])
        app.launch()
        XCTAssertTrue(app.otherElements["screen-root"].waitForExistence(timeout: 15))

        let start = Date()
        let screenVisible = app.otherElements["screen-focus-session"].waitForExistence(timeout: 3)
        let timerVisible = app.staticTexts["focus-timer-remaining"].waitForExistence(timeout: 3)
        let ms = Int(Date().timeIntervalSince(start) * 1000)

        EvidenceWriter.write(
            source: source,
            status: ms <= hardFailMs && screenVisible && timerVisible ? "pass" : "fail",
            durationMs: ms,
            logs: [
                "screen-focus-session=\(screenVisible)",
                "focus-timer-remaining=\(timerVisible)",
                "targetMs=\(targetMs)",
                "hardFailMs=\(hardFailMs)"
            ],
            metrics: ["focusTimerOverlayPaintMs": Double(ms)]
        )

        XCTAssertTrue(screenVisible, "Focus session screen should appear")
        XCTAssertTrue(timerVisible, "Remaining timer label should appear")
        XCTAssertLessThan(
            ms,
            hardFailMs,
            "Focus overlay paint took \(ms)ms — target ≤ \(targetMs)ms, hard fail > \(hardFailMs)ms"
        )
    }

    // MARK: - Real user path: Today → expand row → Start now

    func testFocusTimerOpensInstantlyFromTodayTimeline() throws {
        let source = QASource(
            "PERF-FOCUS-TIMER-TAP",
            document: "Documentation/qa/09-performance-benchmarks.md",
            layer: "L2"
        )

        app.launchArguments = perfLaunchArgs(extra: ["-SeedFocusTask"])
        app.launch()
        waitForBriefing(timeout: 15)
        tapTab("today")
        XCTAssertTrue(app.otherElements["screen-today"].waitForExistence(timeout: 8))

        let card = app.otherElements["timeline-event-card-uitest-focus-task"]
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Seeded UITest focus task should appear on Today timeline")
        card.tap()
        XCTAssertTrue(app.buttons["focus-start-now"].waitForExistence(timeout: 3))

        let start = Date()
        app.buttons["focus-start-now"].tap()

        let screenVisible = app.otherElements["screen-focus-session"].waitForExistence(timeout: 2)
        let timerVisible = app.staticTexts["focus-timer-remaining"].waitForExistence(timeout: 2)
        let ms = Int(Date().timeIntervalSince(start) * 1000)

        EvidenceWriter.write(
            source: source,
            status: ms <= hardFailMs && screenVisible && timerVisible ? "pass" : "fail",
            durationMs: ms,
            logs: [
                "tap-to-screen=\(screenVisible)",
                "tap-to-timer=\(timerVisible)",
                "targetMs=\(targetMs)",
                "hardFailMs=\(hardFailMs)"
            ],
            metrics: ["focusTimerTapOpenMs": Double(ms)]
        )

        XCTAssertTrue(screenVisible, "Focus session screen should appear after Start now")
        XCTAssertTrue(timerVisible, "Remaining timer label should appear after Start now")
        XCTAssertLessThan(
            ms,
            hardFailMs,
            "Focus timer tap open took \(ms)ms — target ≤ \(targetMs)ms, hard fail > \(hardFailMs)ms"
        )
    }

    /// Repeated samples — discard first run (warm SwiftUI caches), average 2–5.
    func testFocusTimerTapOpenLatencyStableAcrossRuns() throws {
        app.launchArguments = perfLaunchArgs(extra: ["-SeedFocusTask"])
        app.launch()
        waitForBriefing(timeout: 15)

        var samples: [Int] = []

        for run in 0..<5 {
            tapTab("today")
            XCTAssertTrue(app.otherElements["screen-today"].waitForExistence(timeout: 8))

            let card = app.otherElements["timeline-event-card-uitest-focus-task"]
            XCTAssertTrue(card.waitForExistence(timeout: 20))
            card.tap()
            XCTAssertTrue(app.buttons["focus-start-now"].waitForExistence(timeout: 3))

            let start = Date()
            app.buttons["focus-start-now"].tap()
            XCTAssertTrue(app.staticTexts["focus-timer-remaining"].waitForExistence(timeout: 2))
            samples.append(Int(Date().timeIntervalSince(start) * 1000))

            app.buttons["focus-session-stop"].tap()
            XCTAssertTrue(app.otherElements["screen-focus-session"].waitForNonExistence(timeout: 3))

            if run == 0 { continue }
        }

        let measured = samples.dropFirst()
        let average = measured.isEmpty ? 0 : measured.reduce(0, +) / measured.count

        EvidenceWriter.write(
            source: QASource("PERF-FOCUS-TIMER-STABLE", document: "Documentation/qa/09-performance-benchmarks.md"),
            status: average <= hardFailMs ? "pass" : "fail",
            durationMs: average,
            logs: ["samplesMs=\(samples)", "averagedRuns=\(Array(measured))"],
            metrics: ["focusTimerTapAverageMs": Double(average)]
        )

        XCTAssertLessThan(
            average,
            hardFailMs,
            "Average tap-to-timer latency \(average)ms exceeds \(hardFailMs)ms (target \(targetMs)ms)"
        )
    }

    // MARK: - Pause / stop controls

    func testPauseUpdatesTimerLabelInstantly() throws {
        let source = QASource(
            "PERF-FOCUS-TIMER-PAUSE",
            document: "Documentation/qa/09-performance-benchmarks.md",
            layer: "L2"
        )

        openAutoStartedFocusSession()

        let start = Date()
        app.buttons["focus-session-pause-toggle"].tap()
        let pausedVisible = app.staticTexts["paused"].waitForExistence(timeout: 2)
        let ms = Int(Date().timeIntervalSince(start) * 1000)

        EvidenceWriter.write(
            source: source,
            status: ms <= hardFailMs && pausedVisible ? "pass" : "fail",
            durationMs: ms,
            metrics: ["focusTimerPauseMs": Double(ms)]
        )

        XCTAssertTrue(pausedVisible, "Paused label should appear immediately")
        XCTAssertLessThan(ms, hardFailMs, "Pause UI took \(ms)ms — target ≤ \(targetMs)ms")
    }

    func testStopDismissesFocusScreenInstantly() throws {
        let source = QASource(
            "PERF-FOCUS-TIMER-STOP",
            document: "Documentation/qa/09-performance-benchmarks.md",
            layer: "L2"
        )

        openAutoStartedFocusSession()

        let start = Date()
        app.buttons["focus-session-stop"].tap()
        let dismissed = app.otherElements["screen-focus-session"].waitForNonExistence(timeout: 2)
        let ms = Int(Date().timeIntervalSince(start) * 1000)

        EvidenceWriter.write(
            source: source,
            status: ms <= hardFailMs && dismissed ? "pass" : "fail",
            durationMs: ms,
            metrics: ["focusTimerStopMs": Double(ms)]
        )

        XCTAssertTrue(dismissed, "Focus screen should dismiss immediately after stop")
        XCTAssertLessThan(ms, hardFailMs, "Stop UI took \(ms)ms — target ≤ \(targetMs)ms")
    }

    func testResumeAfterPauseWithinThreshold() throws {
        openAutoStartedFocusSession()

        app.buttons["focus-session-pause-toggle"].tap()
        XCTAssertTrue(app.staticTexts["paused"].waitForExistence(timeout: 2))

        let start = Date()
        app.buttons["focus-session-pause-toggle"].tap()
        let resumed = app.staticTexts["remaining"].waitForExistence(timeout: 2)
        let ms = Int(Date().timeIntervalSince(start) * 1000)

        EvidenceWriter.write(
            source: QASource("PERF-FOCUS-TIMER-RESUME", document: "Documentation/qa/09-performance-benchmarks.md"),
            status: ms <= hardFailMs && resumed ? "pass" : "fail",
            durationMs: ms,
            metrics: ["focusTimerResumeMs": Double(ms)]
        )

        XCTAssertTrue(resumed, "Remaining label should return after resume")
        XCTAssertLessThan(ms, hardFailMs, "Resume UI took \(ms)ms")
    }

    // MARK: - Helpers

    private func openAutoStartedFocusSession() {
        app.launchArguments = perfLaunchArgs(extra: ["-AutoStartFocusSession"])
        app.launch()
        XCTAssertTrue(app.otherElements["screen-root"].waitForExistence(timeout: 15))
        XCTAssertTrue(
            app.otherElements["screen-focus-session"].waitForExistence(timeout: 20),
            "Focus session should auto-start after UITest bootstrap"
        )
        XCTAssertTrue(app.staticTexts["focus-timer-remaining"].waitForExistence(timeout: 5))
    }
}

private extension XCUIElement {
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !exists { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return !exists
    }
}
