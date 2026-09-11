import XCTest
import LookAfterCore
@testable import LookAfterFeatures

final class LifeAdminBatchCuratorTests: XCTestCase {
    @MainActor
    func testCuratesOverdueBillAndMed() {
        let bill = BillItem(title: "Electric", amount: 80, dueDate: Date().addingTimeInterval(-86400))
        let med = Medication(name: "Med A", dosage: "10mg", scheduledTime: Date(), isTaken: false)
        let batch = LifeAdminBatchCurator.curate(
            LifeAdminBatchCurator.Input(bills: [bill], shoppingItems: [], medications: [med], contacts: [])
        )
        XCTAssertNotNil(batch)
        XCTAssertGreaterThanOrEqual(batch?.items.count ?? 0, 2)
    }
}

final class BadDayDetectorTests: XCTestCase {
    @MainActor
    func testDetectsBadDayFromLowCapacityAndSleep() {
        let signal = BadDayDetector.evaluate(
            BadDayDetector.Input(capacityBand: .recoveryMode, sleepHours: 4.5, deferralCountToday: 3, activeTaskCount: 9)
        )
        XCTAssertNotNil(signal)
        XCTAssertEqual(signal?.recommendedTemplate, .recovery)
    }
}

final class InitiationScriptBuilderTests: XCTestCase {
    @MainActor
    func testBuildsScriptWithSteps() {
        let task = LifeTask(title: "Write report", estimatedMinutes: 60)
        let script = InitiationScriptBuilder.build(task: task, deferralCount: 3)
        XCTAssertEqual(script.durationMinutes, 5)
        XCTAssertFalse(script.steps.isEmpty)
    }

    @MainActor
    func testMicroStartMatchesShortTaskEstimate() {
        let task = LifeTask(title: "Quick tidy", estimatedMinutes: 5)
        let script = InitiationScriptBuilder.build(task: task, deferralCount: 1)
        XCTAssertEqual(script.durationMinutes, 5)
        XCTAssertTrue(script.message.contains("5 minutes"))
        XCTAssertFalse(script.message.contains("2 minutes"))
    }
}
