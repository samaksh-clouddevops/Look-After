import XCTest
@testable import LookAfterFeatures
import LookAfterCore

final class ProactiveBundleBuilderTests: XCTestCase {
    @MainActor
    func testEndOfDayBundleDefersOpenTasks() {
        let task = LifeTask(id: "t1", title: "Open", userId: "u1")
        let action = ProactiveAction(
            kind: .endOfDayClose,
            severity: .medium,
            message: "Close day",
            options: ["Defer to tomorrow"],
            relatedTaskIDs: [task.id]
        )
        let bundle = ProactiveBundleBuilder.bundle(
            for: action,
            context: ProactiveBundleBuilder.BuildContext(tasks: [task])
        )
        XCTAssertEqual(bundle.mutations.count, 1)
        XCTAssertEqual(bundle.mutations.first?.kind, .deferTask)
    }

    @MainActor
    func testBundleCodecRoundTrip() {
        let action = ProactiveAction(
            kind: .waitingMode,
            severity: .medium,
            message: "Gap",
            options: ["Start 5-min"],
            relatedTaskIDs: ["t1"]
        )
        let bundle = ProactiveActionBundle(focusSessionTaskID: "t1", focusSessionMinutes: 5)
        let enriched = ProactiveActionBundleCodec.action(action, attaching: bundle)
        let decoded = ProactiveActionBundleCodec.decode(from: enriched)
        XCTAssertEqual(decoded?.focusSessionTaskID, "t1")
        XCTAssertEqual(decoded?.focusSessionMinutes, 5)
    }
}
