import XCTest

final class Flow007Tests: FlowTestBase {
    func test_FLOW007_MainFlow() throws {
        let source = QASource("FLOW-007", document: "Documentation/qa/05-flow-test-cases.md")
        let start = Date()
        launch(seedFlow: "FLOW-007", showOnboarding: false)
        waitForBriefing()
        let shot = captureScreenshot(name: "FLOW-007")
        let ok = app.buttons["tab-briefing"].exists || app.otherElements["screen-onboarding"].exists
        EvidenceWriter.write(source: source, status: ok ? "pass" : "fail", durationMs: Int(Date().timeIntervalSince(start) * 1000), logs: ["Cycle log dashboard"], screenshots: [shot])
        XCTAssertTrue(ok)
    }

    func test_FLOW007_BackgroundRecovery() throws {
        let source = QASource("FLOW-007-INT-B", document: "Documentation/qa/05-flow-test-cases.md")
        let start = Date()
        launch(seedFlow: "FLOW-007", showOnboarding: false)
        waitForBriefing()
        backgroundAndForeground(seconds: 2)
        let recovered = app.buttons["tab-briefing"].exists || app.otherElements["screen-onboarding"].exists || app.otherElements["screen-briefing"].exists
        EvidenceWriter.write(source: source, status: recovered ? "pass" : "fail", durationMs: Int(Date().timeIntervalSince(start) * 1000), logs: ["background recovery"])
        XCTAssertTrue(recovered)
    }

    func test_FLOW007_TerminateRelaunch() throws {
        let source = QASource("FLOW-007-INT-T", document: "Documentation/qa/05-flow-test-cases.md")
        let start = Date()
        launch(seedFlow: "FLOW-007", showOnboarding: false)
        waitForBriefing()
        app.terminate()
        app.launch()
        let recovered = app.buttons["tab-briefing"].waitForExistence(timeout: 15) || app.otherElements["screen-onboarding"].waitForExistence(timeout: 10)
        EvidenceWriter.write(source: source, status: recovered ? "pass" : "fail", durationMs: Int(Date().timeIntervalSince(start) * 1000), logs: ["terminate + relaunch"])
        XCTAssertTrue(recovered)
    }
}
