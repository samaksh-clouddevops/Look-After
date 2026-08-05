import XCTest

final class Flow001Tests: FlowTestBase {
    func test_FLOW001_MainFlow() throws {
        let source = QASource("FLOW-001", document: "Documentation/qa/05-flow-test-cases.md")
        let start = Date()
        launch(seedFlow: "FLOW-001", showOnboarding: true)

        let onboarding = app.otherElements["screen-onboarding"].waitForExistence(timeout: 10)
        XCTAssertTrue(onboarding, "Onboarding should appear for FLOW-001")

        // Tap through onboarding if continue/skip buttons exist
        if app.buttons["Continue"].exists { app.buttons["Continue"].tap() }
        if app.buttons["Get started"].exists { app.buttons["Get started"].tap() }
        if app.buttons["Skip"].exists { app.buttons["Skip"].tap() }

        // Complete onboarding by marking profile complete via UI or wait for briefing
        _ = app.otherElements["screen-briefing"].waitForExistence(timeout: 20)
            || app.buttons["tab-briefing"].waitForExistence(timeout: 20)

        let shot = captureScreenshot(name: "FLOW-001")
        let reachedBriefing = app.buttons["tab-briefing"].exists || app.otherElements["screen-briefing"].exists
        EvidenceWriter.write(
            source: source,
            status: reachedBriefing ? "pass" : "fail",
            durationMs: Int(Date().timeIntervalSince(start) * 1000),
            logs: ["Onboarding flow to briefing", "reachedBriefing: \(reachedBriefing)"],
            screenshots: [shot]
        )
        XCTAssertTrue(reachedBriefing)
    }

    func test_FLOW001_BackgroundRecovery() throws {
        let source = QASource("FLOW-001-INT-B", document: "Documentation/qa/05-flow-test-cases.md")
        let start = Date()
        launch(seedFlow: "FLOW-001", showOnboarding: true)
        _ = app.otherElements["screen-onboarding"].waitForExistence(timeout: 10)
            || app.buttons["tab-briefing"].waitForExistence(timeout: 10)
        backgroundAndForeground()
        let recovered = app.buttons["tab-briefing"].exists
            || app.otherElements["screen-onboarding"].exists
            || app.otherElements["screen-briefing"].exists
        EvidenceWriter.write(source: source, status: recovered ? "pass" : "fail", durationMs: Int(Date().timeIntervalSince(start) * 1000), logs: ["background recovery"])
        XCTAssertTrue(recovered)
    }

    func test_FLOW001_TerminateRelaunch() throws {
        let source = QASource("FLOW-001-INT-T", document: "Documentation/qa/05-flow-test-cases.md")
        let start = Date()
        launch(seedFlow: "FLOW-001", showOnboarding: true)
        _ = app.otherElements["screen-onboarding"].waitForExistence(timeout: 10)
        app.terminate()
        app.launch()
        let recovered = app.otherElements["screen-onboarding"].waitForExistence(timeout: 10)
            || app.buttons["tab-briefing"].waitForExistence(timeout: 10)
        EvidenceWriter.write(source: source, status: recovered ? "pass" : "fail", durationMs: Int(Date().timeIntervalSince(start) * 1000), logs: ["terminate + relaunch"])
        XCTAssertTrue(recovered)
    }
}
