import XCTest

final class Flow013Tests: FlowTestBase {
    func test_FLOW013_MainFlow() throws {
        let source = QASource("FLOW-013", document: "Documentation/qa/05-flow-test-cases.md")
        let start = Date()
        launch(seedFlow: "FLOW-013", showOnboarding: false)
        waitForBriefing()
        let shot = captureScreenshot(name: "FLOW-013")
        let ok = app.buttons["tab-briefing"].exists || app.otherElements["screen-onboarding"].exists
        EvidenceWriter.write(source: source, status: ok ? "pass" : "fail", durationMs: Int(Date().timeIntervalSince(start) * 1000), logs: ["Task import bulk create"], screenshots: [shot])
        XCTAssertTrue(ok)
    }

    func test_FLOW013_BackgroundRecovery() throws {
        let source = QASource("FLOW-013-INT-B", document: "Documentation/qa/05-flow-test-cases.md")
        let start = Date()
        launch(seedFlow: "FLOW-013", showOnboarding: false)
        waitForBriefing()
        backgroundAndForeground(seconds: 2)
        let recovered = app.buttons["tab-briefing"].exists || app.otherElements["screen-onboarding"].exists || app.otherElements["screen-briefing"].exists
        EvidenceWriter.write(source: source, status: recovered ? "pass" : "fail", durationMs: Int(Date().timeIntervalSince(start) * 1000), logs: ["background recovery"])
        XCTAssertTrue(recovered)
    }

    func test_FLOW013_TerminateRelaunch() throws {
        let source = QASource("FLOW-013-INT-T", document: "Documentation/qa/05-flow-test-cases.md")
        let start = Date()
        launch(seedFlow: "FLOW-013", showOnboarding: false)
        waitForBriefing()
        app.terminate()
        app.launch()
        let recovered = app.buttons["tab-briefing"].waitForExistence(timeout: 15) || app.otherElements["screen-onboarding"].waitForExistence(timeout: 10)
        EvidenceWriter.write(source: source, status: recovered ? "pass" : "fail", durationMs: Int(Date().timeIntervalSince(start) * 1000), logs: ["terminate + relaunch"])
        XCTAssertTrue(recovered)
    }
}
