import XCTest

/// Adaptive guided tour — visibility, navigation, and skip.
final class FeatureTourUITests: FlowTestBase {

    func test_FeatureTour_AppearsAndAdvances() throws {
        let source = QASource("TOUR-001", document: "Documentation/qa/05-flow-test-cases.md")
        let start = Date()

        launch(seedFlow: "FLOW-002", showOnboarding: false, extra: [
            "-ShowFeatureTour",
            "-SkipLiveActivity"
        ])

        waitForBriefing(timeout: 20)

        let tour = app.otherElements["screen-feature-tour"]
        let appeared = tour.waitForExistence(timeout: 12)
        XCTAssertTrue(appeared, "Feature tour overlay should appear")

        // Welcome step → next
        let next = app.buttons["tour-next"]
        if next.waitForExistence(timeout: 4) {
            next.tap()
        }

        // After advance the tour should still be presented
        let stillVisible = tour.waitForExistence(timeout: 4)
        let shot = captureScreenshot(name: "TOUR-001-step")

        // Skip should dismiss
        let skip = app.buttons["tour-skip"]
        if skip.waitForExistence(timeout: 3) {
            skip.tap()
        }
        let dismissed = !tour.waitForExistence(timeout: 3)

        EvidenceWriter.write(
            source: source,
            status: appeared && stillVisible && dismissed ? "pass" : "fail",
            durationMs: Int(Date().timeIntervalSince(start) * 1000),
            logs: [
                "appeared=\(appeared)",
                "stillVisible=\(stillVisible)",
                "dismissed=\(dismissed)"
            ],
            screenshots: [shot]
        )
        XCTAssertTrue(appeared && stillVisible && dismissed)
    }

    func test_FeatureTour_BackAndFinishIdentifiers() throws {
        let source = QASource("TOUR-002", document: "Documentation/qa/05-flow-test-cases.md")
        let start = Date()

        launch(seedFlow: "FLOW-002", showOnboarding: false, extra: [
            "-ShowFeatureTour",
            "-SkipLiveActivity"
        ])
        waitForBriefing(timeout: 20)

        let tour = app.otherElements["screen-feature-tour"]
        XCTAssertTrue(tour.waitForExistence(timeout: 12))

        app.buttons["tour-next"].tap()
        // Back appears after leaving step 0
        let back = app.buttons["tour-back"]
        let backVisible = back.waitForExistence(timeout: 4)
        if backVisible {
            back.tap()
        }

        // Skip remaining
        if app.buttons["tour-skip"].waitForExistence(timeout: 3) {
            app.buttons["tour-skip"].tap()
        }

        EvidenceWriter.write(
            source: source,
            status: backVisible ? "pass" : "fail",
            durationMs: Int(Date().timeIntervalSince(start) * 1000),
            logs: ["backVisible=\(backVisible)"]
        )
        XCTAssertTrue(backVisible)
    }
}
