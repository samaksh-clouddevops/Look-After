import XCTest
@testable import LookAfterCore

final class TimeConstraintTests: XCTestCase {

    func testHardenSoftenLadder() {
        XCTAssertEqual(TimeConstraint.fluid.hardened(), .flexible)
        XCTAssertEqual(TimeConstraint.flexible.hardened(), .anchored)
        XCTAssertEqual(TimeConstraint.anchored.hardened(), .anchored)

        XCTAssertEqual(TimeConstraint.anchored.softened(), .flexible)
        XCTAssertEqual(TimeConstraint.flexible.softened(), .fluid)
        XCTAssertEqual(TimeConstraint.fluid.softened(), .fluid)
    }

    func testSchedulingModeBridge() {
        XCTAssertEqual(TimeConstraint.from(schedulingMode: .fixedTime), .anchored)
        XCTAssertEqual(TimeConstraint.from(schedulingMode: .flexible), .flexible)
        XCTAssertEqual(TimeConstraint.from(schedulingMode: nil), .flexible)
        XCTAssertEqual(TimeConstraint.anchored.asSchedulingMode, .fixedTime)
        XCTAssertEqual(TimeConstraint.fluid.asSchedulingMode, .flexible)
    }

    func testAnchoredRubberBandCapsAtMax() {
        let max = TimeConstraintPhysics.anchoredMaxTranslation
        let small = TimeConstraintPhysics.anchoredTranslation(rawDelta: 10)
        let large = TimeConstraintPhysics.anchoredTranslation(rawDelta: 400)
        XCTAssertLessThan(abs(small), abs(large))
        XCTAssertLessThanOrEqual(abs(large), max + 0.001)
        XCTAssertEqual(
            TimeConstraintPhysics.anchoredTranslation(rawDelta: -400),
            -TimeConstraintPhysics.anchoredTranslation(rawDelta: 400),
            accuracy: 0.0001
        )
    }

    func testLifeTaskApplyConstraintKeepsSchedulingModeAligned() {
        var task = LifeTask(title: "Deep work", userId: "u1")
        XCTAssertEqual(task.timeConstraintValue, .flexible)

        task.applyTimeConstraint(.anchored)
        XCTAssertEqual(task.timeConstraint, .anchored)
        XCTAssertEqual(task.schedulingMode, .fixedTime)
        XCTAssertFalse(task.timeConstraintValue.isSchedulerMovable)

        task.applyTimeConstraint(.fluid)
        XCTAssertEqual(task.timeConstraint, .fluid)
        XCTAssertEqual(task.schedulingMode, .flexible)
        XCTAssertTrue(task.timeConstraintValue.isSchedulerMovable)
    }

    func testCodableRoundTrip() throws {
        let original = TimeConstraint.anchored
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TimeConstraint.self, from: data)
        XCTAssertEqual(decoded, original)

        var task = LifeTask(title: "Standup", schedulingMode: .fixedTime, userId: "u")
        task.applyTimeConstraint(.anchored)
        let taskData = try JSONEncoder().encode(task)
        let decodedTask = try JSONDecoder().decode(LifeTask.self, from: taskData)
        XCTAssertEqual(decodedTask.timeConstraint, .anchored)
    }
}
