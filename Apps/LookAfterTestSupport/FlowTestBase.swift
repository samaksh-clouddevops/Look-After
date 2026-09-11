import Foundation
import XCTest

/// Requirement traceability metadata for EVP Phase 2.
struct QASource {
    let requirementId: String
    let sourceDocument: String
    let validationLayer: String

    init(_ requirementId: String, document: String, layer: String = "L2") {
        self.requirementId = requirementId
        self.sourceDocument = document
        self.validationLayer = layer
    }
}

enum EvidenceWriter {
    static func write(
        source: QASource,
        status: String,
        durationMs: Int,
        logs: [String] = [],
        screenshots: [String] = [],
        metrics: [String: Double] = [:]
    ) {
        let repoRoot = discoverRepoRoot()
        let dir = (repoRoot as NSString).appendingPathComponent("Documentation/qa/.engine/evidence")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = (dir as NSString).appendingPathComponent("\(source.requirementId).json")
        let payload: [String: Any] = [
            "requirementId": source.requirementId,
            "sourceDocument": source.sourceDocument,
            "validationLayer": source.validationLayer,
            "status": status,
            "durationMs": durationMs,
            "logs": logs,
            "screenshots": screenshots,
            "metrics": metrics,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    static func discoverRepoRoot() -> String {
        if let env = ProcessInfo.processInfo.environment["LOOKAFTER_REPO_ROOT"],
           !env.isEmpty,
           FileManager.default.fileExists(atPath: (env as NSString).appendingPathComponent("Documentation/qa")) {
            return env
        }
        // Walk from this source file when tests run from DerivedData.
        let probe = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // LookAfterTestSupport
            .deletingLastPathComponent() // Apps
            .deletingLastPathComponent() // Look-After root
        if FileManager.default.fileExists(atPath: probe.appendingPathComponent("Documentation/qa").path) {
            return probe.path
        }
        var current = FileManager.default.currentDirectoryPath
        while true {
            let qa = (current as NSString).appendingPathComponent("Documentation/qa")
            if FileManager.default.fileExists(atPath: qa) { return current }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current { break }
            current = parent
        }
        return NSHomeDirectory()
    }
}

enum LaunchArguments {
    static func uiTesting(seedFlow: String = "FLOW-002", showOnboarding: Bool = false) -> [String] {
        var args = ["-UITesting", "-SeedFlow", seedFlow]
        if showOnboarding { args.append("-ShowOnboarding") }
        return args
    }
}

class FlowTestBase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func launch(seedFlow: String = "FLOW-002", showOnboarding: Bool = false, extra: [String] = []) {
        app.launchArguments = LaunchArguments.uiTesting(seedFlow: seedFlow, showOnboarding: showOnboarding) + extra
        app.launch()
    }

    func waitForOnboarding(timeout: TimeInterval = 15) {
        let onboarding = app.otherElements["screen-onboarding"].waitForExistence(timeout: timeout)
        XCTAssertTrue(onboarding, "Onboarding screen should appear")
    }

    func waitForBriefing(timeout: TimeInterval = 15) {
        // Auth cover must not block — dismiss via guest if still on Auth.
        if app.buttons["Continue as Guest (Try Offline)"].waitForExistence(timeout: 2) {
            app.buttons["Continue as Guest (Try Offline)"].tap()
        }
        let briefing = app.otherElements["screen-briefing"].waitForExistence(timeout: timeout)
            || app.buttons["tab-briefing"].waitForExistence(timeout: timeout)
            || app.otherElements["screen-root"].waitForExistence(timeout: 3)
        XCTAssertTrue(briefing, "Briefing screen should appear")
    }

    func tapTab(_ name: String) {
        app.buttons["tab-\(name.lowercased())"].tap()
    }

    func captureScreenshot(name: String) -> String {
        let shot = XCUIScreen.main.screenshot()
        let dir = (EvidenceWriter.discoverRepoRoot() as NSString)
            .appendingPathComponent("Documentation/qa/.engine/screenshots")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = (dir as NSString).appendingPathComponent("\(name).png")
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: path))
        return path
    }

    func backgroundAndForeground(seconds: UInt32 = 2) {
        XCUIDevice.shared.press(.home)
        sleep(seconds)
        app.activate()
    }
}
