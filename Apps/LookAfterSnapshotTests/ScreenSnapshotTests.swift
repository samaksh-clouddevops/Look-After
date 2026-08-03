import XCTest

/// Visual regression for documented screens S01–S47.
final class ScreenSnapshotTests: FlowTestBase {
    private var recordBaselines: Bool {
        ProcessInfo.processInfo.arguments.contains("-RecordBaselines")
    }

    func testAllDocumentedScreens() throws {
        launch(seedFlow: "FLOW-002")
        waitForBriefing()

        for screen in ScreenNavigator.allScreens {
            let source = QASource(screen.id, document: "Documentation/qa/04-screen-test-cases.md", layer: "L2")
            let start = Date()

            if screen.platform != "ios" {
                EvidenceWriter.write(
                    source: source,
                    status: "skip",
                    durationMs: 0,
                    logs: ["Platform \(screen.platform) — snapshot captured on iOS simulator only for S01–S42"]
                )
                continue
            }

            let reached = screen.navigate(app)
            let shot = XCUIScreen.main.screenshot()
            let result = SnapshotEngine.compareScreenshot(shot, screenId: screen.id, recordBaseline: recordBaselines)

            let layoutOk = auditLayout(app: app, identifier: screen.identifier)
            let status: String
            if !reached && !recordBaselines {
                status = "fail"
            } else if !result.passed || !layoutOk {
                status = "fail"
            } else {
                status = "pass"
            }

            EvidenceWriter.write(
                source: source,
                status: status,
                durationMs: Int(Date().timeIntervalSince(start) * 1000),
                logs: [result.message, "reached: \(reached)", "layoutOk: \(layoutOk)", "diffRatio: \(result.diffRatio)"],
                screenshots: [SnapshotEngine.baselinePath(screenId: screen.id)],
                metrics: ["diffRatio": result.diffRatio]
            )

            if status == "fail" && !recordBaselines {
                XCTFail("\(screen.id): \(result.message) reached=\(reached) layout=\(layoutOk)")
            }
        }
    }

    func testOnboardingScreen() throws {
        app.launchArguments = LaunchArguments.uiTesting(seedFlow: "FLOW-001", showOnboarding: true)
        app.launch()
        let onboarding = app.otherElements["screen-onboarding"].waitForExistence(timeout: 10)
        XCTAssertTrue(onboarding, "S25 onboarding should appear with -ShowOnboarding")
        let result = SnapshotEngine.compareScreenshot(XCUIScreen.main.screenshot(), screenId: "S25", recordBaseline: recordBaselines)
        EvidenceWriter.write(
            source: QASource("S25", document: "Documentation/qa/04-screen-test-cases.md"),
            status: result.passed ? "pass" : "fail",
            durationMs: 0,
            logs: [result.message]
        )
    }

    private func auditLayout(app: XCUIApplication, identifier: String) -> Bool {
        let element = app.otherElements[identifier]
        guard element.exists else { return true }
        let frame = element.frame
        guard frame.width > 0, frame.height > 0 else { return false }
        return true
    }
}
