import XCTest
@testable import LookAfterCore

final class TaskEphemeralityTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()
    private let day = Date(timeIntervalSince1970: 1_720_000_000)

    func testLunchDoesNotShiftPastBoundingBox() {
        let start = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
        var lunch = LifeTask(
            id: "lunch",
            title: "Lunch",
            status: .pending,
            estimatedMinutes: 45,
            scheduledDate: calendar.startOfDay(for: day),
            scheduledTime: start,
            timeConstraint: .flexible,
            expirationPolicy: .endOfDay,
            temporalBoundingBox: TemporalBoundingBox(earliestStartHour: 11, latestStartHour: 15),
            scheduledEndTime: start.addingTimeInterval(45 * 60),
            userId: "u"
        )
        // Anchor the whole afternoon so only late gaps remain.
        let anchors = (15..<21).map { h -> LifeTask in
            let s = calendar.date(bySettingHour: h, minute: 0, second: 0, of: day)!
            return LifeTask(
                id: "a-\(h)", title: "Meeting", status: .pending, estimatedMinutes: 55,
                scheduledDate: calendar.startOfDay(for: day), scheduledTime: s,
                timeConstraint: .anchored, scheduledEndTime: s.addingTimeInterval(55 * 60), userId: "u"
            )
        }
        // Overlap lunch with first anchor
        let block = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
        let clash = LifeTask(
            id: "clash", title: "All hands", status: .pending, estimatedMinutes: 180,
            scheduledDate: calendar.startOfDay(for: day), scheduledTime: block,
            timeConstraint: .anchored, scheduledEndTime: block.addingTimeInterval(180 * 60), userId: "u"
        )
        let result = ConflictResolutionCascade.resolve(
            tasks: [lunch, clash] + anchors, on: day, calendar: calendar
        )
        let out = result.tasks.first { $0.id == "lunch" }!
        XCTAssertTrue(
            out.status == .expired || decision(result, "lunch") == .expired,
            "Lunch must not park at night — got \(out.status) \(String(describing: decision(result, "lunch")))"
        )
        XCTAssertNil(out.scheduledTime)
        _ = lunch
    }

    func testSemanticCollisionSupersedesRolloverWorkout() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: day)!
        let yStart = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: yesterday)!
        var missed = LifeTask(
            id: "gym-mon",
            title: "Gym Push Day",
            lifeArea: .health,
            status: .pending,
            estimatedMinutes: 60,
            scheduledDate: calendar.startOfDay(for: yesterday),
            scheduledTime: yStart,
            expirationPolicy: .infinite,
            collisionStrategy: .dropOldest,
            userId: "u"
        )
        missed.semanticProfile = TaskSemanticProfile(semanticType: .physicalActivity)
        let tStart = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day)!
        var todayGym = LifeTask(
            id: "gym-tue",
            title: "Gym Pull Day",
            lifeArea: .health,
            status: .pending,
            estimatedMinutes: 60,
            scheduledDate: calendar.startOfDay(for: day),
            scheduledTime: tStart,
            expirationPolicy: .infinite,
            collisionStrategy: .dropOldest,
            userId: "u"
        )
        todayGym.semanticProfile = TaskSemanticProfile(semanticType: .physicalActivity)
        XCTAssertEqual(TaskReaper.collisionKey(for: missed), TaskReaper.collisionKey(for: todayGym))

        let park = ParkedTaskQueueStore.inMemory()
        let result = DayScheduleReconciler.sweepDayBoundary(
            tasks: [missed, todayGym],
            from: yesterday,
            to: day,
            now: day.addingTimeInterval(8 * 3600),
            calendar: calendar,
            parkedQueue: park
        )
        let mon = result.tasks.first { $0.id == "gym-mon" }!
        XCTAssertEqual(mon.status, .superseded)
        XCTAssertTrue(park.snapshot().entries.isEmpty)
    }

    func testDistillerMentionsExpiredAndSupersededCalmly() {
        let actions = CascadeDistiller.distill(decisions: [
            .init(taskID: "1", action: .expired, reason: "reaper"),
            .init(taskID: "2", action: .superseded, reason: "collision"),
        ])
        XCTAssertTrue(actions.contains { $0.lowercased().contains("skipped") || $0.lowercased().contains("ephemeral") || $0.lowercased().contains("time-bound") })
        XCTAssertTrue(actions.contains { $0.lowercased().contains("duplicate") || $0.lowercased().contains("dropped") })
    }

    func testMidnightEndOfDaySkipsMeal() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: day)!
        let start = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: yesterday)!
        let lunch = LifeTask(
            id: "l",
            title: "Lunch",
            status: .pending,
            estimatedMinutes: 40,
            scheduledDate: calendar.startOfDay(for: yesterday),
            scheduledTime: start,
            expirationPolicy: .endOfDay,
            userId: "u"
        )
        let park = ParkedTaskQueueStore.inMemory()
        let result = DayScheduleReconciler.sweepDayBoundary(
            tasks: [lunch], from: yesterday, to: day,
            now: day.addingTimeInterval(7 * 3600),
            calendar: calendar, parkedQueue: park
        )
        XCTAssertEqual(result.tasks.first?.status, .skipped)
        XCTAssertTrue(park.snapshot().entries.isEmpty)
    }

    private func decision(_ result: ConflictCascadeResult, _ id: String) -> ConflictCascadeAction? {
        result.decisions.first { $0.taskID == id }?.action
    }
}
