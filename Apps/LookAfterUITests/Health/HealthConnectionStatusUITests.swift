import XCTest

/// Health connection status messaging — connected-but-empty vs not-connected.
final class HealthConnectionStatusUITests: FlowTestBase {

    func testConnectedButEmptyShowsWaitingForDataNotLinkPrompt() throws {
        launch(extra: ["-MockHealthStatus", "waitingForData"])
        waitForBriefing()
        openSettings()

        let statusRow = app.otherElements["settings-health-status-row"]
        XCTAssertTrue(statusRow.waitForExistence(timeout: 8), "Settings health status row should appear")
        XCTAssertTrue(statusRow.staticTexts["Connected, but no data yet"].exists)
        XCTAssertFalse(statusRow.staticTexts["Link Apple Health"].exists)

        EvidenceWriter.write(
            source: QASource("HEALTH-STATUS-WAITING", document: "apple-watch-health-troubleshooting"),
            status: "pass",
            durationMs: 0
        )
    }

    func testNotConnectedShowsConnectAppleHealth() throws {
        launch(extra: ["-MockHealthStatus", "notSetUp"])
        waitForBriefing()
        openSettings()

        let statusRow = app.otherElements["settings-health-status-row"]
        XCTAssertTrue(statusRow.waitForExistence(timeout: 8), "Settings health status row should appear")
        XCTAssertTrue(statusRow.staticTexts["Connect Apple Health"].exists)

        EvidenceWriter.write(
            source: QASource("HEALTH-STATUS-NOT-SETUP", document: "apple-watch-health-troubleshooting"),
            status: "pass",
            durationMs: 0
        )
    }

    private func openSettings() {
        let settingsButton = app.buttons["Settings"]
        if settingsButton.waitForExistence(timeout: 5) {
            settingsButton.tap()
        }
    }
}
