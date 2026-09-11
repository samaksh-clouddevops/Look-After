import Foundation
import XCTest

/// Sequential product-flow screenshots for the UI/UX agent (step = one intentional action + settle).
///
/// IDs are `F##` so they do not collide with static screen catalog `S##`.
enum UXFlowCapture {
    struct Step: Sendable {
        let id: String
        let title: String
        let notes: String
        let perform: @Sendable (XCUIApplication) -> Bool
    }

    /// Primary ADHD journey: Briefing → Today → Plan → Tasks → Capture → Brain → You → Settings.
    nonisolated(unsafe) static let functionalityFlow: [Step] = [
        Step(
            id: "F01",
            title: "Briefing first fold",
            notes: "Greeting, Start my day, Glance in fold, tab bar"
        ) { app in
            ScreenNavigator.dismissBlockingOverlays(app)
            tapTab(app, "briefing")
            scrollToTop(app)
            settle(0.35)
            return reached(app, ["screen-briefing"], labels: ["Start my day", "Good afternoon", "Good morning"])
        },
        Step(
            id: "F02",
            title: "Briefing scrolled chapters",
            notes: "How you are doing / sleep-tasks-health below fold"
        ) { app in
            tapTab(app, "briefing")
            // One swipe keeps chapter headers below the status bar (avoids clock overlay on stats).
            swipeContentUp(app, times: 1)
            settle(0.35)
            return reached(app, ["screen-briefing"], labels: ["How you're doing", "Where you're at", "Health", "sleep", "tasks"])
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "How")).firstMatch.exists
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Where")).firstMatch.exists
        },
        Step(
            id: "F03",
            title: "Briefing customize",
            notes: "Layout / life filters sheet from slider control"
        ) { app in
            ScreenNavigator.dismissBlockingOverlays(app)
            tapTab(app, "briefing")
            softTap(app.buttons["nav-briefing-overflow"])
            softTap(app.buttons["nav-briefing-customize"])
            softTap(app.buttons["Customize Briefing"])
            softTap(app.buttons["Briefing layout and life filters"])
            settle(0.5)
            return reached(
                app,
                ["screen-daily-briefing-customization"],
                labels: ["Customize", "Life", "Filters", "Briefing"]
            ) || app.sheets.firstMatch.exists
        },
        Step(
            id: "F04",
            title: "Briefing after customize dismiss",
            notes: "Back to Briefing without Auth leak"
        ) { app in
            dismissSheets(app)
            tapTab(app, "briefing")
            scrollToTop(app)
            return reached(app, ["screen-briefing"], labels: ["Start my day"])
        },
        Step(
            id: "F05",
            title: "Today after Start my day",
            notes: "Hero DO THIS NOW, coach hierarchy, Plan toolbar"
        ) { app in
            ScreenNavigator.dismissBlockingOverlays(app)
            tapTab(app, "briefing")
            softTap(app.buttons["briefing-continue-cta"])
            softTap(app.buttons["Start my day"])
            tapTab(app, "today")
            scrollToTop(app)
            settle(0.9)
            scrollToTop(app)
            settle(0.45)
            // FLOW-T1: hero must exist — do not accept screen-today / "Today" alone.
            return requiresHero(app)
        },
        Step(
            id: "F06",
            title: "Today Schedule preview",
            notes: "Scroll to Up next + Schedule 2-row preview"
        ) { app in
            tapTab(app, "today")
            swipeContentUp(app, times: 2)
            return reached(app, ["screen-today"], labels: ["Schedule", "Up next", "Full timeline"])
        },
        Step(
            id: "F07",
            title: "Full timeline",
            notes: "Full timeline from Schedule link"
        ) { app in
            tapTab(app, "today")
            softTap(app.buttons["today-schedule-full-timeline"])
            softTap(app.buttons["Full timeline →"])
            softTap(app.buttons["View full timeline"])
            settle(0.55)
            return reached(app, ["screen-live-timeline"], labels: ["Timeline", "NOW", "LATE"])
                || app.otherElements["screen-today"].exists
        },
        Step(
            id: "F08",
            title: "Today after timeline dismiss",
            notes: "Return to Today first fold"
        ) { app in
            dismissSheets(app)
            tapTab(app, "today")
            scrollToTop(app)
            settle(0.35)
            return requiresHero(app)
        },
        Step(
            id: "F09",
            title: "Plan With Me",
            notes: "Plan sparkles sheet / conversation"
        ) { app in
            dismissSheets(app)
            tapTab(app, "today")
            settle(0.4)
            // Toolbar sparkles only — label is "Plan", id is nav-plan-assistant.
            let planBtn = app.buttons["nav-plan-assistant"]
            if planBtn.waitForExistence(timeout: 2.0) {
                planBtn.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            } else {
                softTap(app.buttons["Plan"])
            }
            settle(1.0)
            let sheet = app.descendants(matching: .any).matching(identifier: "screen-planning-conversation").firstMatch
            let sheetAlt = app.descendants(matching: .any).matching(identifier: "screen-assistant-sheet").firstMatch
            if sheet.waitForExistence(timeout: 3.0) || sheetAlt.waitForExistence(timeout: 1.5) {
                return true
            }
            return app.staticTexts["Plan With Me"].waitForExistence(timeout: 2.0)
        },
        Step(
            id: "F10",
            title: "Today after Plan dismiss",
            notes: "Collapse Plan without losing Today"
        ) { app in
            softTap(app.buttons["Collapse planning assistant"])
            dismissSheets(app)
            tapTab(app, "today")
            scrollToTop(app)
            settle(0.35)
            return requiresHero(app) || reached(app, ["screen-today"], labels: ["Today", "DO THIS NOW"])
        },
        Step(
            id: "F11",
            title: "All tasks",
            notes: "Task list via Today overflow"
        ) { app in
            return ScreenNavigator.navigate(to: "S14", app: app)
                || reached(app, ["screen-task-list"], labels: ["All Tasks", "All tasks"])
        },
        Step(
            id: "F12",
            title: "Today after tasks dismiss",
            notes: "Pop task list back to Today"
        ) { app in
            ScreenNavigator.dismissBlockingOverlays(app)
            tapTab(app, "today")
            scrollToTop(app)
            return reached(app, ["screen-today"], labels: ["Today"])
        },
        Step(
            id: "F13",
            title: "Capture empty",
            notes: "Composer + disabled Save affordance"
        ) { app in
            // Do not dismiss overlays after opening — that closes Capture.
            openCapture(app)
            settle(0.5)
            return reached(
                app,
                ["screen-capture", "capture-composer", "capture-save-disabled", "capture-text-field"],
                labels: ["Capture", "Save", "Speak"]
            )
        },
        Step(
            id: "F14",
            title: "Capture with text Save ready",
            notes: "Typed content enables Save"
        ) { app in
            if !reached(app, ["screen-capture", "capture-composer"], labels: ["Capture"]) {
                openCapture(app)
                settle(0.4)
            }
            let field = firstExisting(
                app.textViews["capture-text-field"],
                app.textFields["capture-text-field"],
                app.textViews.matching(identifier: "capture-text-field").element,
                app.textFields.matching(identifier: "capture-text-field").element
            )
            if field.waitForExistence(timeout: 3) {
                softTap(field)
                field.typeText("Call dentist tomorrow morning")
            }
            settle(0.4)
            return app.buttons["capture-save"].waitForExistence(timeout: 2)
                || app.buttons["Save"].exists
        },
        Step(
            id: "F15",
            title: "Capture dismissed",
            notes: "Close Capture; tabs usable again"
        ) { app in
            ScreenNavigator.dismissBlockingOverlays(app)
            tapTab(app, "briefing")
            return reached(app, ["screen-briefing"], labels: ["Start my day", "Briefing"])
                || reached(app, ["screen-today"], labels: ["Today"])
        },
        Step(
            id: "F16",
            title: "Brain dashboard",
            notes: "Orb + Decide for me affordance"
        ) { app in
            ScreenNavigator.dismissBlockingOverlays(app)
            tapTab(app, "brain")
            settle(0.45)
            return reached(
                app,
                ["screen-brain-dashboard", "brain-voice-orb"],
                labels: ["Decide for me", "Executive Brain", "Ask Brain"]
            )
        },
        Step(
            id: "F17",
            title: "You profile",
            notes: "You tab / executive profile"
        ) { app in
            tapTab(app, "you")
            settle(0.4)
            return reached(app, ["screen-executive-profile", "screen-you"], labels: ["You", "Preferences"])
        },
        Step(
            id: "F18",
            title: "Settings",
            notes: "App settings from You"
        ) { app in
            tapTab(app, "you")
            softTap(app.buttons["nav-open-settings"])
            softTap(app.buttons["Preferences"])
            softTap(app.buttons["Settings"])
            settle(0.5)
            return reached(app, ["screen-settings"], labels: ["Settings", "API", "Health"])
        },
        Step(
            id: "F19",
            title: "Tab bar on Briefing",
            notes: "4 tabs + Capture FAB flush check"
        ) { app in
            dismissSheets(app)
            ScreenNavigator.dismissBlockingOverlays(app)
            tapTab(app, "briefing")
            settle(0.35)
            return app.buttons["tab-briefing"].waitForExistence(timeout: 3)
                && app.buttons["tab-capture"].exists
        },
    ]

    // MARK: - Helpers

    private static func settle(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private static func softTap(_ element: XCUIElement) {
        guard element.waitForExistence(timeout: 1.2) else { return }
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private static func tapTab(_ app: XCUIApplication, _ name: String) {
        softTap(app.buttons["tab-\(name.lowercased())"])
        settle(0.25)
    }

    private static func openCapture(_ app: XCUIApplication) {
        ScreenNavigator.dismissBlockingOverlays(app)
        // Only the FAB id — never label CONTAINS "Capture" (matches multiple nodes).
        softTap(app.buttons["tab-capture"])
        settle(0.45)
    }

    /// Prefer identifier hits; fall back to visible labels (SwiftUI sometimes hides ids from otherElements).
    private static func reached(
        _ app: XCUIApplication,
        _ identifiers: [String],
        labels: [String] = []
    ) -> Bool {
        for id in identifiers {
            let any = app.descendants(matching: .any).matching(identifier: id).firstMatch
            if any.waitForExistence(timeout: 1.5) { return true }
            if app.otherElements[id].exists { return true }
            if app.buttons[id].exists { return true }
        }
        for label in labels {
            if app.staticTexts[label].exists { return true }
            if app.buttons[label].exists { return true }
            if app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", label)).firstMatch.exists {
                return true
            }
        }
        return false
    }

    /// Wave 1 exit: hero id or visible "DO THIS NOW" — not screen-today alone.
    private static func requiresHero(_ app: XCUIApplication) -> Bool {
        let hero = app.descendants(matching: .any).matching(identifier: "today-do-this-now").firstMatch
        if hero.waitForExistence(timeout: 2.5) { return true }
        if app.otherElements["today-do-this-now"].exists { return true }
        if app.staticTexts["DO THIS NOW"].exists { return true }
        return app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "DO THIS NOW")).firstMatch.exists
    }

    private static func scrollToTop(_ app: XCUIApplication) {
        for _ in 0..<3 {
            app.swipeDown()
            settle(0.15)
        }
    }

    private static func swipeContentUp(_ app: XCUIApplication, times: Int) {
        for _ in 0..<times {
            app.swipeUp()
            settle(0.3)
        }
    }

    private static func dismissSheets(_ app: XCUIApplication) {
        for label in ["Done", "Close", "Collapse planning assistant", "Not now"] {
            softTap(app.buttons[label])
        }
        softTap(app.navigationBars.buttons["Done"])
        softTap(app.navigationBars.buttons.element(boundBy: 0))
        if app.sheets.firstMatch.exists {
            app.swipeDown()
            settle(0.25)
        }
        ScreenNavigator.dismissBlockingOverlays(app)
    }

    private static func firstExisting(_ elements: XCUIElement...) -> XCUIElement {
        elements.first(where: { $0.exists }) ?? elements[0]
    }
}
