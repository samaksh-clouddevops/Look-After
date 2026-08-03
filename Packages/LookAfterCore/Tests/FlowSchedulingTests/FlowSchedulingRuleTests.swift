import XCTest
@testable import LookAfterCore

final class FlowSchedulingRuleTests: XCTestCase {

    // MARK: - ContinueTaskRule

    func testContinueTaskRulePrefersInProgressTask() {
        let inProgress = FlowSchedulingTestFixtures.task(title: "API Review", status: .inProgress, estimatedMinutes: 18)
        let pending = FlowSchedulingTestFixtures.task(title: "Email", status: .pending)
        let input = FlowSchedulingTestFixtures.input(tasks: [pending, inProgress])
        var state = MutableSchedulingState()
        ContinueTaskRule().apply(to: &state, context: FlowSchedulingTestFixtures.context(from: input))

        XCTAssertEqual(state.heroTask?.title, "API Review")
        XCTAssertEqual(state.actionType, .continue)
        XCTAssertTrue(state.appliedRuleIDs.contains("ContinueTaskRule"))
    }

    func testContinueTaskRulePrefersActiveFlowSession() {
        let task = FlowSchedulingTestFixtures.task(id: "t1", title: "Write Spec", status: .inProgress, estimatedMinutes: 25)
        let session = FlowSessionState(isActive: true, taskID: "t1", elapsedSeconds: 300, targetSeconds: 1500)
        let input = FlowSchedulingTestFixtures.input(tasks: [task], session: session)
        var state = MutableSchedulingState()
        ContinueTaskRule().apply(to: &state, context: FlowSchedulingTestFixtures.context(from: input))

        XCTAssertEqual(state.heroTask?.id, "t1")
        XCTAssertEqual(state.actionType, .continue)
    }

    // MARK: - MeetingSoonRule

    func testMeetingSoonRuleCapsDuration() {
        let event = CalendarEventReference(
            id: "e1", title: "Sync", startDate: Date(), endDate: Date(), minutesUntilStart: 30
        )
        let longTask = FlowSchedulingTestFixtures.task(title: "Architecture", estimatedMinutes: 90)
        var env = EnvironmentContext(energyScore: 0.7, nextEvent: event, timeOfDay: .morning)
        let input = FlowSchedulingTestFixtures.input(tasks: [longTask], environment: env)
        var state = MutableSchedulingState(heroTask: longTask, suggestedDurationMinutes: 90)
        MeetingSoonRule().apply(to: &state, context: FlowSchedulingTestFixtures.context(from: input))

        XCTAssertEqual(state.maxDurationCap, 30)
        XCTAssertTrue(state.appliedRuleIDs.contains("MeetingSoonRule"))
    }

    // MARK: - LowEnergyRule

    func testLowEnergyRuleSelectsLighterTask() {
        let demanding = FlowSchedulingTestFixtures.task(
            title: "Deep Design",
            difficulty: .hard,
            requiredEnergy: .peak,
            priority: .high
        )
        let light = FlowSchedulingTestFixtures.task(title: "Quick Reply", estimatedMinutes: 10, difficulty: .easy)
        var env = EnvironmentContext(energyScore: 0.25, timeOfDay: .morning)
        let input = FlowSchedulingTestFixtures.input(tasks: [demanding, light], environment: env)
        var state = MutableSchedulingState(heroTask: demanding, suggestedDurationMinutes: 60)
        LowEnergyRule().apply(to: &state, context: FlowSchedulingTestFixtures.context(from: input))

        XCTAssertEqual(state.heroTask?.title, "Quick Reply")
        XCTAssertEqual(state.actionType, .startSmall)
        XCTAssertFalse(state.rescheduledTasks.isEmpty)
    }

    // MARK: - DeepWorkWindowRule

    func testDeepWorkWindowRulePromotesHardTask() {
        let deep = FlowSchedulingTestFixtures.task(
            title: "Architecture Design",
            estimatedMinutes: 60,
            difficulty: .hard,
            priority: .high
        )
        let quick = FlowSchedulingTestFixtures.task(title: "Inbox", estimatedMinutes: 10)
        var env = EnvironmentContext(energyScore: 0.8, freeBlockMinutes: 120, timeOfDay: .morning)
        let input = FlowSchedulingTestFixtures.input(tasks: [quick, deep], environment: env)
        var state = MutableSchedulingState(heroTask: quick, suggestedDurationMinutes: 10)
        DeepWorkWindowRule().apply(to: &state, context: FlowSchedulingTestFixtures.context(from: input))

        XCTAssertEqual(state.heroTask?.title, "Architecture Design")
        XCTAssertEqual(state.actionType, .startDeep)
    }

    // MARK: - DeferralRule

    func testDeferralRuleOffersMicroChunk() {
        let task = FlowSchedulingTestFixtures.task(id: "deferred-task", title: "Taxes")
        let behavior = BehaviorMemorySnapshot(
            deferralRecords: [TaskDeferralRecord(taskID: "deferred-task", deferralCount: 3)]
        )
        let input = FlowSchedulingTestFixtures.input(tasks: [task], behavior: behavior)
        var state = MutableSchedulingState(heroTask: task, suggestedDurationMinutes: 30)
        DeferralRule().apply(to: &state, context: FlowSchedulingTestFixtures.context(from: input))

        XCTAssertEqual(state.actionType, .tryMicro)
        XCTAssertEqual(state.suggestedDurationMinutes, 5)
        XCTAssertEqual(state.coachMoment?.momentType, .microChunkOffer)
    }

    // MARK: - BatteryRule

    func testBatteryRuleShortensSession() {
        let env = EnvironmentContext(energyScore: 0.6, timeOfDay: .morning, batteryLevel: 0.15)
        let input = FlowSchedulingTestFixtures.input(
            tasks: [FlowSchedulingTestFixtures.task(title: "Task")],
            environment: env
        )
        var state = MutableSchedulingState(suggestedDurationMinutes: 45)
        BatteryRule().apply(to: &state, context: FlowSchedulingTestFixtures.context(from: input))

        XCTAssertEqual(state.maxDurationCap, 15)
    }

    func testBatteryRuleLowPowerModeUsesShorterCap() {
        let env = EnvironmentContext(energyScore: 0.6, timeOfDay: .morning, isLowPowerMode: true)
        let input = FlowSchedulingTestFixtures.input(
            tasks: [FlowSchedulingTestFixtures.task(title: "Task")],
            environment: env
        )
        var state = MutableSchedulingState(suggestedDurationMinutes: 45)
        BatteryRule().apply(to: &state, context: FlowSchedulingTestFixtures.context(from: input))

        XCTAssertEqual(state.maxDurationCap, 10)
    }

    // MARK: - CalendarGapRule

    func testCalendarGapRuleSetsFlowWindow() {
        let start = FlowSchedulingTestFixtures.morningDate
        let end = start.addingTimeInterval(7200)
        let env = EnvironmentContext(
            energyScore: 0.7,
            freeBlockMinutes: 120,
            flowWindow: DateInterval(start: start, end: end),
            timeOfDay: .morning
        )
        let input = FlowSchedulingTestFixtures.input(
            tasks: [FlowSchedulingTestFixtures.task(title: "Focus")],
            environment: env
        )
        var state = MutableSchedulingState(heroTask: input.pendingTasks.first)
        CalendarGapRule().apply(to: &state, context: FlowSchedulingTestFixtures.context(from: input))

        XCTAssertEqual(state.flowWindow?.start, start)
        XCTAssertTrue(state.appliedRuleIDs.contains("CalendarGapRule"))
    }
}
