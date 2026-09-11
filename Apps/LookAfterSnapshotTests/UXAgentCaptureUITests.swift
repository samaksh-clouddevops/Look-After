import XCTest

/// Captures Look After screens into `screenshots/ux-agent/` for Cursor UI/UX agent review.
///
/// Prefer **full functionality flow** (`testExportFullFunctionalityFlowForUXAgent`) so the agent
/// sees each step of the product journey, not only destination tabs.
///
/// Run via `./Scripts/capture-ux-review.sh` or xcodebuild `-only-testing:…`.
final class UXAgentCaptureUITests: FlowTestBase {
    private lazy var stamp: String = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }()

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Keep exporting remaining steps when one navigation is flaky.
        continueAfterFailure = true
    }

    /// Step-by-step product journey (F01–F19) + dark Briefing — default for UI/UX agent.
    func testExportFullFunctionalityFlowForUXAgent() throws {
        UXReviewCapture.resetLatestDirectory()

        launch(seedFlow: "FLOW-002", extra: ["-ExportUXReview"])
        waitForBriefing()
        XCTAssertFalse(
            app.otherElements["screen-auth"].exists,
            "Auth must not remain after UITest session seed"
        )
        ScreenNavigator.dismissBlockingOverlays(app)
        UXReviewCapture.writeManifestHeader(stamp: stamp)

        for step in UXFlowCapture.functionalityFlow {
            let reached = step.perform(app)
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            let path = UXReviewCapture.save(
                XCUIScreen.main.screenshot(),
                screenId: step.id,
                title: step.title,
                reached: reached,
                stamp: stamp,
                extraNotes: step.notes
            )
            EvidenceWriter.write(
                source: QASource(step.id, document: "Documentation/qa/ux-agent-full-flow-shot-list.md"),
                status: reached ? "pass" : "fail",
                durationMs: 0,
                logs: [step.notes, path],
                screenshots: [path]
            )
        }

        // Dark Briefing contrast pair.
        app.terminate()
        launch(seedFlow: "FLOW-002", extra: ["-ExportUXReview", "-UIPreferredInterfaceStyle", "Dark"])
        waitForBriefing()
        XCTAssertFalse(app.otherElements["screen-auth"].exists)
        softTapTab("briefing")
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        UXReviewCapture.save(
            XCUIScreen.main.screenshot(),
            screenId: "F01-dark",
            title: "Briefing first fold dark",
            reached: true,
            stamp: stamp,
            extraNotes: "Dark mode contrast check on first fold"
        )
    }

    /// Legacy destination-only core set (S02/S05/…). Prefer the full flow test above.
    func testExportCoreScreensForUXAgent() throws {
        UXReviewCapture.resetLatestDirectory()

        launch(seedFlow: "FLOW-002", extra: ["-ExportUXReview"])
        waitForBriefing()
        XCTAssertFalse(
            app.otherElements["screen-auth"].exists,
            "Auth must not remain after UITest session seed"
        )
        ScreenNavigator.dismissBlockingOverlays(app)
        UXReviewCapture.writeManifestHeader(stamp: stamp)

        for screen in UXReviewCapture.coreScreens {
            let reached = ScreenNavigator.navigate(to: screen.id, app: app)
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            let path = UXReviewCapture.save(
                XCUIScreen.main.screenshot(),
                screenId: screen.id,
                title: screen.title,
                reached: reached,
                stamp: stamp,
                extraNotes: screen.notes
            )
            EvidenceWriter.write(
                source: QASource(screen.id, document: "Documentation/qa/ux-agent-screenshot-pipeline.md"),
                status: reached ? "pass" : "fail",
                durationMs: 0,
                logs: [screen.notes, path],
                screenshots: [path]
            )
            if screen.id == "S39" {
                ScreenNavigator.dismissBlockingOverlays(app)
            }
        }

        app.terminate()
        launch(seedFlow: "FLOW-002", extra: ["-ExportUXReview", "-UIPreferredInterfaceStyle", "Dark"])
        waitForBriefing()
        XCTAssertFalse(app.otherElements["screen-auth"].exists)
        _ = ScreenNavigator.navigate(to: "S02", app: app)
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        UXReviewCapture.save(
            XCUIScreen.main.screenshot(),
            screenId: "S02-dark",
            title: "Briefing dark",
            reached: true,
            stamp: stamp,
            extraNotes: "Dark mode contrast check"
        )
    }

    private func softTapTab(_ name: String) {
        let button = app.buttons["tab-\(name.lowercased())"]
        guard button.waitForExistence(timeout: 3) else { return }
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
}
