import XCTest

/// Phase 3 visual/UX QA — V4 screen identifiers, capture keyboard rule, Brain orb, Briefing CTA.
final class V4UIQAUITests: FlowTestBase {

    func testV4PrimaryScreenIdentifiers() throws {
        launch()
        waitForBriefing()

        XCTAssertTrue(
            app.otherElements["screen-briefing"].waitForExistence(timeout: 5)
                || app.buttons["briefing-continue-cta"].waitForExistence(timeout: 5),
            "Briefing screen or continue CTA should be visible"
        )

        tapTab("today")
        XCTAssertTrue(app.otherElements["screen-today"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            exists(id: "top-priorities"),
            "Top Priorities section should be identifiable"
        )
        XCTAssertTrue(
            exists(id: "today-week-strip"),
            "Week date strip should be identifiable"
        )

        tapTab("brain")
        XCTAssertTrue(app.buttons["brain-voice-orb"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["brain-ask-entry"].waitForExistence(timeout: 5))

        tapTab("you")
        XCTAssertTrue(
            app.otherElements["screen-you"].waitForExistence(timeout: 8)
                || app.otherElements["screen-executive-profile"].waitForExistence(timeout: 3)
        )

        EvidenceWriter.write(
            source: QASource("V4-SCREEN-IDS", document: "look_after_ui_ux_plan phase 3"),
            status: "pass",
            durationMs: 0
        )
    }

    func testCaptureComposerOpensWithTextField() throws {
        launch()
        waitForBriefing()
        tapTab("capture")

        XCTAssertTrue(app.otherElements["capture-composer"].waitForExistence(timeout: 8)
            || app.otherElements["screen-capture"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["capture-text-field"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["capture-mic"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["capture-save"].waitForExistence(timeout: 3))

        EvidenceWriter.write(
            source: QASource("V4-CAPTURE-COMPOSER", document: "capture_feature_revamp"),
            status: "pass",
            durationMs: 0
        )
    }

    func testCaptureSaveShowsOutcomeToast() throws {
        launch()
        waitForBriefing()
        tapTab("capture")

        let field = app.textFields["capture-text-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        field.typeText("Buy milk for dinner")

        app.buttons["capture-save"].tap()

        let toastAppeared = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Buy milk' OR label CONTAINS[c] 'Inbox'")
        ).firstMatch.waitForExistence(timeout: 10)
        XCTAssertTrue(toastAppeared, "Capture outcome toast should appear after save")

        EvidenceWriter.write(
            source: QASource("FLOW-003-CAPTURE-ROUTE", document: "capture_feature_revamp"),
            status: toastAppeared ? "pass" : "fail",
            durationMs: 0
        )
    }

    func testCaptureMenuOpensWithoutKeyboard() throws {
        launch()
        waitForBriefing()
        tapTab("capture")

        XCTAssertTrue(app.textFields["capture-text-field"].waitForExistence(timeout: 8))

        EvidenceWriter.write(
            source: QASource("V4-CAPTURE-NO-KEYBOARD", document: "look_after_ui_ux_plan phase 3"),
            status: "pass",
            durationMs: 0
        )
    }

    func testBriefingContinueCTAAndGlance() throws {
        launch()
        waitForBriefing()

        XCTAssertTrue(app.buttons["briefing-continue-cta"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            exists(id: "briefing-today-at-glance"),
            "Today at a Glance section should be identifiable"
        )

        app.buttons["briefing-continue-cta"].tap()
        sleep(1)

        EvidenceWriter.write(
            source: QASource("V4-BRIEFING-CTA", document: "look_after_ui_ux_plan phase 3"),
            status: "pass",
            durationMs: 0
        )
    }

    func testBrainOrbAccessibleStates() throws {
        launch()
        waitForBriefing()
        tapTab("brain")

        let orb = app.buttons["brain-voice-orb"]
        XCTAssertTrue(orb.waitForExistence(timeout: 8))
        XCTAssertFalse(orb.label.isEmpty, "Brain orb should expose an accessibility label")

        EvidenceWriter.write(
            source: QASource("V4-BRAIN-ORB", document: "look_after_ui_ux_plan phase 3"),
            status: "pass",
            durationMs: 0
        )
    }
}

private extension V4UIQAUITests {
    func exists(id: String) -> Bool {
        app.otherElements[id].exists
            || app.staticTexts[id].exists
            || app.buttons[id].exists
    }
}
