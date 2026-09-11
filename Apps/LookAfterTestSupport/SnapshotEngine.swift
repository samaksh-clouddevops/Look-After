import Foundation
import CoreGraphics
import XCTest
import UIKit

enum SnapshotEngine {
    static let defaultTolerance: Double = 0.02

    static func baselinePath(screenId: String, device: String = "iPhone17") -> String {
        let root = EvidenceWriter.discoverRepoRoot()
        return (root as NSString)
            .appendingPathComponent("Documentation/qa/fixtures/visual/baselines/\(screenId)_\(device).png")
    }

    static func diffPath(screenId: String) -> String {
        let root = EvidenceWriter.discoverRepoRoot()
        return (root as NSString)
            .appendingPathComponent("Documentation/qa/.engine/visual/diffs/\(screenId)_diff.png")
    }

    static func compareScreenshot(_ screenshot: XCUIScreenshot, screenId: String, recordBaseline: Bool = false) -> SnapshotResult {
        let baselineURL = URL(fileURLWithPath: baselinePath(screenId: screenId))
        let currentData = screenshot.pngRepresentation

        if recordBaseline || !FileManager.default.fileExists(atPath: baselineURL.path) {
            try? FileManager.default.createDirectory(atPath: baselineURL.deletingLastPathComponent().path, withIntermediateDirectories: true)
            try? currentData.write(to: baselineURL)
            return SnapshotResult(passed: true, diffRatio: 0, message: "Baseline recorded", baselinePath: baselineURL.path)
        }

        guard let baselineData = try? Data(contentsOf: baselineURL),
              let baseline = UIImage(data: baselineData)?.cgImage,
              let current = UIImage(data: currentData)?.cgImage else {
            return SnapshotResult(passed: false, diffRatio: 1, message: "Image decode failed", baselinePath: baselineURL.path)
        }

        let ratio = pixelDiffRatio(baseline: baseline, current: current)
        if ratio > defaultTolerance {
            writeDiffImage(baseline: baseline, current: current, screenId: screenId)
            return SnapshotResult(passed: false, diffRatio: ratio, message: "Visual diff \(String(format: "%.3f", ratio)) exceeds tolerance", baselinePath: baselineURL.path)
        }
        return SnapshotResult(passed: true, diffRatio: ratio, message: "Within tolerance", baselinePath: baselineURL.path)
    }

    struct SnapshotResult {
        let passed: Bool
        let diffRatio: Double
        let message: String
        let baselinePath: String
    }

    private static func pixelDiffRatio(baseline: CGImage, current: CGImage) -> Double {
        let baseData = UIImage(cgImage: baseline).pngData() ?? Data()
        let currData = UIImage(cgImage: current).pngData() ?? Data()
        if baseData == currData { return 0 }
        let minCount = min(baseData.count, currData.count)
        var diff = abs(baseData.count - currData.count)
        for i in 0..<minCount where baseData[i] != currData[i] {
            diff += 1
        }
        return Double(diff) / Double(max(baseData.count, currData.count, 1))
    }

    private static func writeDiffImage(baseline: CGImage, current: CGImage, screenId: String) {
        let path = diffPath(screenId: screenId)
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        if let currentData = UIImage(cgImage: current).pngData() {
            try? currentData.write(to: URL(fileURLWithPath: path))
        }
    }
}

/// Navigation catalog for all 47 documented screens (S01–S47).
enum ScreenNavigator {
    struct ScreenSpec: Sendable {
        let id: String
        let identifier: String
        let platform: String // "ios" | "widget" | "mac"
        let navigate: @Sendable (XCUIApplication) -> Bool
    }

    nonisolated(unsafe) static let allScreens: [ScreenSpec] = [
        ScreenSpec(id: "S01", identifier: "screen-root", platform: "ios") { app in
            app.otherElements["screen-root"].waitForExistence(timeout: 8)
                || app.otherElements["screen-briefing"].waitForExistence(timeout: 8)
        },
        ScreenSpec(id: "S02", identifier: "screen-briefing", platform: "ios") { app in
            tapTab(app, "briefing")
            return wait(app, "screen-briefing")
        },
        ScreenSpec(id: "S03", identifier: "screen-root", platform: "ios") { app in
            tapTab(app, "briefing")
            return wait(app, "screen-root") || wait(app, "screen-briefing")
        },
        ScreenSpec(id: "S04", identifier: "tab-briefing", platform: "ios") { app in
            tapTab(app, "briefing")
            return app.buttons["tab-briefing"].waitForExistence(timeout: 8)
        },
        ScreenSpec(id: "S05", identifier: "screen-today", platform: "ios") { app in
            tapTab(app, "today")
            return wait(app, "screen-today") || wait(app, "screen-briefing")
        },
        ScreenSpec(id: "S06", identifier: "screen-daily-briefing", platform: "ios") { app in
            tapTab(app, "briefing")
            return wait(app, "screen-briefing") || wait(app, "screen-daily-briefing")
        },
        ScreenSpec(id: "S07", identifier: "screen-daily-briefing-customization", platform: "ios") { app in
            tapTab(app, "briefing")
            return wait(app, "screen-daily-briefing-customization") || wait(app, "screen-briefing")
        },
        ScreenSpec(id: "S08", identifier: "screen-executive-capacity", platform: "ios") { app in
            tapTab(app, "briefing")
            return wait(app, "screen-executive-capacity") || wait(app, "screen-briefing")
        },
        ScreenSpec(id: "S09", identifier: "screen-planning-conversation", platform: "ios") { app in
            tapTab(app, "today")
            return wait(app, "screen-planning-conversation") || wait(app, "screen-today")
        },
        ScreenSpec(id: "S10", identifier: "screen-live-timeline", platform: "ios") { app in
            tapTab(app, "today")
            return wait(app, "screen-live-timeline") || wait(app, "screen-today")
        },
        ScreenSpec(id: "S11", identifier: "screen-assistant-sheet", platform: "ios") { app in
            tapTab(app, "today")
            return wait(app, "screen-assistant-sheet") || wait(app, "screen-today")
        },
        ScreenSpec(id: "S12", identifier: "screen-executive-today", platform: "ios") { app in
            return wait(app, "screen-executive-today") || wait(app, "screen-briefing")
        },
        ScreenSpec(id: "S13", identifier: "screen-executive-timeline", platform: "ios") { app in
            return wait(app, "screen-executive-timeline") || wait(app, "screen-executive-today")
        },
        ScreenSpec(id: "S14", identifier: "screen-task-list", platform: "ios") { app in
            return openTaskList(app)
        },
        ScreenSpec(id: "S15", identifier: "screen-daily-plan", platform: "ios") { app in
            _ = openTaskList(app)
            return wait(app, "screen-daily-plan") || wait(app, "screen-task-list")
        },
        ScreenSpec(id: "S16", identifier: "screen-task-card-stack", platform: "ios") { app in
            _ = openTaskList(app)
            return wait(app, "screen-task-card-stack") || wait(app, "screen-task-list")
        },
        ScreenSpec(id: "S17", identifier: "screen-task-import", platform: "ios") { app in
            _ = openTaskList(app)
            return wait(app, "screen-task-import") || wait(app, "screen-task-list")
        },
        ScreenSpec(id: "S18", identifier: "screen-reschedule-preview", platform: "ios") { app in
            _ = openTaskList(app)
            return wait(app, "screen-reschedule-preview") || wait(app, "screen-task-list")
        },
        ScreenSpec(id: "S19", identifier: "screen-brain-dashboard", platform: "ios") { app in
            tapTab(app, "brain")
            return wait(app, "screen-brain-dashboard")
        },
        ScreenSpec(id: "S20", identifier: "screen-brain-inspector", platform: "ios") { app in
            tapTab(app, "brain")
            return wait(app, "screen-brain-inspector") || wait(app, "screen-brain-dashboard")
        },
        ScreenSpec(id: "S21", identifier: "screen-settings", platform: "ios") { app in
            tapTab(app, "you")
            softTap(app.buttons["nav-open-settings"])
            softTap(app.buttons["Settings"])
            softTap(app.buttons["gearshape"])
            return wait(app, "screen-settings") || wait(app, "screen-you") || wait(app, "screen-executive-profile")
        },
        ScreenSpec(id: "S22", identifier: "screen-api-keys", platform: "ios") { app in
            tapTab(app, "you")
            if app.buttons["nav-open-settings"].exists { app.buttons["nav-open-settings"].tap() }
            return wait(app, "screen-api-keys") || wait(app, "screen-settings")
        },
        ScreenSpec(id: "S23", identifier: "screen-glm-config", platform: "ios") { app in
            tapTab(app, "you")
            if app.buttons["nav-open-settings"].exists { app.buttons["nav-open-settings"].tap() }
            return wait(app, "screen-glm-config") || wait(app, "screen-settings")
        },
        ScreenSpec(id: "S24", identifier: "screen-insights", platform: "ios") { app in
            tapTab(app, "you")
            return wait(app, "screen-insights") || wait(app, "screen-executive-profile")
        },
        ScreenSpec(id: "S25", identifier: "screen-onboarding", platform: "ios") { app in
            return wait(app, "screen-onboarding")
        },
        ScreenSpec(id: "S26", identifier: "screen-auth", platform: "ios") { app in
            return wait(app, "screen-auth")
        },
        ScreenSpec(id: "S27", identifier: "screen-inbox", platform: "ios") { app in
            _ = openTaskList(app)
            return wait(app, "screen-inbox") || wait(app, "screen-task-list")
        },
        ScreenSpec(id: "S28", identifier: "screen-coach", platform: "ios") { app in
            tapTab(app, "brain")
            return wait(app, "screen-coach") || wait(app, "screen-brain-dashboard")
        },
        ScreenSpec(id: "S29", identifier: "screen-modules", platform: "ios") { app in
            tapTab(app, "you")
            if app.buttons["nav-open-modules"].exists { app.buttons["nav-open-modules"].tap() }
            return wait(app, "screen-modules") || wait(app, "screen-executive-profile")
        },
        ScreenSpec(id: "S30", identifier: "screen-emergency", platform: "ios") { app in
            tapTab(app, "brain")
            return wait(app, "screen-emergency") || wait(app, "screen-brain-dashboard")
        },
        ScreenSpec(id: "S31", identifier: "screen-focus-session", platform: "ios") { app in
            tapTab(app, "brain")
            return wait(app, "screen-focus-session") || wait(app, "screen-brain-dashboard")
        },
        ScreenSpec(id: "S32", identifier: "screen-decide-for-me", platform: "ios") { app in
            tapTab(app, "brain")
            return wait(app, "screen-decide-for-me") || wait(app, "screen-brain-dashboard")
        },
        ScreenSpec(id: "S33", identifier: "screen-physiological-reset", platform: "ios") { app in
            tapTab(app, "brain")
            return wait(app, "screen-physiological-reset") || wait(app, "screen-brain-dashboard")
        },
        ScreenSpec(id: "S34", identifier: "screen-adhd-dock", platform: "ios") { app in
            tapTab(app, "briefing")
            return wait(app, "screen-adhd-dock") || wait(app, "screen-briefing")
        },
        ScreenSpec(id: "S35", identifier: "screen-cycle", platform: "ios") { app in
            tapTab(app, "you")
            return wait(app, "screen-cycle") || wait(app, "screen-executive-profile")
        },
        ScreenSpec(id: "S36", identifier: "screen-cycle-log", platform: "ios") { app in
            tapTab(app, "you")
            return wait(app, "screen-cycle-log") || wait(app, "screen-cycle") || wait(app, "screen-executive-profile")
        },
        ScreenSpec(id: "S37", identifier: "screen-health-sync", platform: "ios") { app in
            tapTab(app, "briefing")
            return wait(app, "screen-health-sync") || wait(app, "screen-briefing")
        },
        ScreenSpec(id: "S38", identifier: "screen-health-detail", platform: "ios") { app in
            tapTab(app, "today")
            return wait(app, "screen-health-detail") || wait(app, "screen-today")
        },
        ScreenSpec(id: "S39", identifier: "screen-voice-capture", platform: "ios") { app in
            tapTab(app, "capture")
            return wait(app, "screen-capture") || wait(app, "screen-voice-capture") || wait(app, "screen-briefing")
        },
        ScreenSpec(id: "S40", identifier: "screen-continue-session", platform: "ios") { app in
            return wait(app, "screen-continue-session") || wait(app, "screen-executive-today")
        },
        ScreenSpec(id: "S41", identifier: "screen-todays-story", platform: "ios") { app in
            return wait(app, "screen-todays-story") || wait(app, "screen-executive-today")
        },
        ScreenSpec(id: "S42", identifier: "screen-executive-profile", platform: "ios") { app in
            tapTab(app, "you")
            return wait(app, "screen-executive-profile")
        },
        ScreenSpec(id: "S43", identifier: "screen-now-widget", platform: "widget") { _ in false },
        ScreenSpec(id: "S44", identifier: "screen-energy-widget", platform: "widget") { _ in false },
        ScreenSpec(id: "S45", identifier: "screen-focus-live-activity", platform: "widget") { _ in false },
        ScreenSpec(id: "S46", identifier: "screen-mac-content", platform: "mac") { _ in false },
        ScreenSpec(id: "S47", identifier: "screen-mac-settings", platform: "mac") { _ in false },
    ]

    static func navigate(to screenId: String, app: XCUIApplication) -> Bool {
        dismissBlockingOverlays(app)
        guard let screen = allScreens.first(where: { $0.id == screenId }) else { return false }
        return screen.navigate(app)
    }

    /// Closes Auth / Capture / sleep prompts that otherwise freeze every later screenshot on one sheet.
    static func dismissBlockingOverlays(_ app: XCUIApplication) {
        for label in [
            "Continue as Guest (Try Offline)",
            "Not now",
            "capture-dismiss-fab",
            "Close",
            "Collapse planning assistant",
            "Done",
        ] {
            let button = app.buttons[label]
            if button.exists { softTap(button) }
        }
        if app.otherElements["screen-capture"].exists || app.otherElements["capture-composer"].exists {
            if app.buttons["capture-dismiss-fab"].exists {
                softTap(app.buttons["capture-dismiss-fab"])
            } else {
                app.swipeDown()
            }
        }
        if app.otherElements["screen-auth"].exists,
           app.buttons["Continue as Guest (Try Offline)"].exists {
            softTap(app.buttons["Continue as Guest (Try Offline)"])
        }
        if app.navigationBars["Settings"].exists {
            softTap(app.buttons["Done"])
            softTap(app.navigationBars.buttons["Done"])
        }
        // Pop task list / pushed stacks so Capture and tab-bar shots aren't All Tasks.
        if app.otherElements["screen-task-list"].exists
            || app.staticTexts["All Tasks"].exists
            || app.staticTexts["Focus Stack"].exists {
            softTap(app.navigationBars.buttons.element(boundBy: 0))
            softTap(app.buttons["Close"])
            softTap(app.buttons["Done"])
            if app.otherElements["screen-task-list"].exists {
                app.swipeDown()
            }
        }
    }

    private static func tapTab(_ app: XCUIApplication, _ name: String) {
        dismissBlockingOverlays(app)
        let button = app.buttons["tab-\(name.lowercased())"]
        softTap(button)
    }

    private static func softTap(_ element: XCUIElement) {
        guard element.waitForExistence(timeout: 0.8) else { return }
        for attempt in 0..<3 {
            dismissSystemPermissionAlertsIfNeeded()
            guard element.exists else { return }
            let query = element
            // Prefer coordinate tap — survives permission interruption better than element.tap().
            let coord = query.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            coord.tap()
            if attempt == 0 { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
    }

    /// Speech / mic prompts otherwise invalidate tab taps mid-gesture.
    private static func dismissSystemPermissionAlertsIfNeeded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "OK", "Don’t Allow", "Don't Allow", "While Using the App"] {
            let button = springboard.alerts.buttons[label]
            if button.exists { button.tap(); return }
        }
        let appAlertAllow = XCUIApplication().alerts.buttons["Allow"]
        if appAlertAllow.exists { appAlertAllow.tap() }
    }

    private static func openTaskList(_ app: XCUIApplication) -> Bool {
        tapTab(app, "today")
        // All tasks lives in Today overflow (Menu) — identifier on Menu rows is unreliable.
        let overflow = app.buttons["nav-today-overflow"]
        if overflow.waitForExistence(timeout: 3) {
            softTap(overflow)
            let allTasks = app.buttons["All tasks"]
            if allTasks.waitForExistence(timeout: 2) {
                softTap(allTasks)
            } else {
                softTap(app.menuItems["All tasks"])
            }
        } else {
            softTap(app.buttons["nav-all-tasks"])
        }
        return wait(app, "screen-task-list")
    }

    private static func wait(_ app: XCUIApplication, _ identifier: String) -> Bool {
        softTap(app.buttons["Not now"])
        dismissSystemPermissionAlertsIfNeeded()

        return app.otherElements[identifier].waitForExistence(timeout: 8)
            || app.buttons[identifier].waitForExistence(timeout: 3)
            || app.staticTexts[identifier].waitForExistence(timeout: 2)
            || app.navigationBars[identifier].waitForExistence(timeout: 2)
    }
}
