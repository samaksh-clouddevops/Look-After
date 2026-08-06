import XCTest
@testable import LookAfterCore

final class WeeklyReviewAggregatorTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    /// Fixed Monday 2024-07-01 12:00 UTC
    private var weekEnding: Date {
        calendar.date(from: DateComponents(year: 2024, month: 7, day: 7, hour: 12))!
    }

    func testWeekBoundsAreSevenDaysInclusive() {
        let bounds = WeeklyReviewAggregator.weekBounds(ending: weekEnding, calendar: calendar)
        let days = calendar.dateComponents([.day], from: bounds.start, to: bounds.endInclusive).day
        XCTAssertEqual(days, 6)
        XCTAssertEqual(calendar.component(.day, from: bounds.start), 1)
        XCTAssertEqual(calendar.component(.day, from: bounds.endInclusive), 7)
    }

    func testFiltersLogsOutsideWindow() {
        let bounds = WeeklyReviewAggregator.weekBounds(ending: weekEnding, calendar: calendar)
        let inside = CascadeActionRecord(
            kind: .superseded, timestamp: bounds.start.addingTimeInterval(3600), durationMinutes: 0
        )
        let before = CascadeActionRecord(
            kind: .expired,
            timestamp: bounds.start.addingTimeInterval(-86_400),
            durationMinutes: 0
        )
        let after = CascadeActionRecord(
            kind: .expired,
            timestamp: bounds.endExclusive.addingTimeInterval(60),
            durationMinutes: 0
        )
        let summary = WeeklyReviewAggregator.aggregate(
            logs: [inside, before, after],
            lifeState: LifeState(),
            weekEnding: weekEnding,
            calendar: calendar
        )
        XCTAssertEqual(summary.tasksSupersededCount, 1)
        XCTAssertEqual(summary.tasksExpiredCount, 0)
    }

    func testTimeReclaimedSumsSabotageDurations() {
        let t = weekEnding.addingTimeInterval(-2 * 86_400)
        let logs = [
            CascadeActionRecord(kind: .sabotageAuction, timestamp: t, durationMinutes: 90),
            CascadeActionRecord(kind: .sabotageAuction, timestamp: t, durationMinutes: 60),
            CascadeActionRecord(kind: .shiftedLater, timestamp: t, durationMinutes: 45)
        ]
        let summary = WeeklyReviewAggregator.aggregate(
            logs: logs,
            lifeState: LifeState(),
            weekEnding: weekEnding,
            calendar: calendar
        )
        XCTAssertEqual(summary.sabotageAuctionsTriggered, 2)
        XCTAssertEqual(summary.timeReclaimedHours, 2.5, accuracy: 0.001)
    }

    func testFlexibleShiftsRequireThirtyMinutes() {
        let t = weekEnding.addingTimeInterval(-86_400)
        let logs = [
            CascadeActionRecord(kind: .shiftedLater, timestamp: t, durationMinutes: 30),
            CascadeActionRecord(kind: .shiftedLater, timestamp: t, durationMinutes: 29),
            CascadeActionRecord(kind: .shiftedLater, timestamp: t, durationMinutes: 90)
        ]
        let summary = WeeklyReviewAggregator.aggregate(
            logs: logs,
            lifeState: LifeState(),
            weekEnding: weekEnding,
            calendar: calendar
        )
        XCTAssertEqual(summary.flexibleShiftsExecuted, 2)
    }

    func testFocusHoursFromCompletedTasks() {
        let t = weekEnding.addingTimeInterval(-3 * 86_400)
        var done = LifeTask(title: "Deep work", status: .completed, estimatedMinutes: 90, completedAt: t)
        done.actualMinutes = 120
        let pending = LifeTask(title: "Open", status: .pending, estimatedMinutes: 60)
        var old = LifeTask(
            title: "Last month",
            status: .completed,
            estimatedMinutes: 200,
            completedAt: t.addingTimeInterval(-30 * 86_400)
        )
        _ = old
        let state = LifeState(activeTasks: [done, pending, old], consecutiveHighLoadDays: 0)
        let summary = WeeklyReviewAggregator.aggregate(
            logs: [],
            lifeState: state,
            weekEnding: weekEnding,
            calendar: calendar
        )
        XCTAssertEqual(summary.totalFocusHoursCompleted, 2.0, accuracy: 0.001)
    }

    func testEquilibriumBasePenaltyAndBonus() {
        // base 0.85 - 2*0.05 + 1*0.08 = 0.83
        let score = WeeklyReviewAggregator.computeEquilibrium(
            highLoadStreakDays: 2,
            sabotageAuctionsTriggered: 1
        )
        XCTAssertEqual(score, 0.83, accuracy: 0.0001)
    }

    func testEquilibriumClampsToFloorAndCeiling() {
        let floor = WeeklyReviewAggregator.computeEquilibrium(
            highLoadStreakDays: 20,
            sabotageAuctionsTriggered: 0
        )
        XCTAssertEqual(floor, 0.2, accuracy: 0.0001)

        let ceil = WeeklyReviewAggregator.computeEquilibrium(
            highLoadStreakDays: 0,
            sabotageAuctionsTriggered: 10
        )
        XCTAssertEqual(ceil, 1.0, accuracy: 0.0001)
    }

    func testHighLoadStreakFlowsFromLifeState() {
        let summary = WeeklyReviewAggregator.aggregate(
            logs: [],
            lifeState: LifeState(consecutiveHighLoadDays: 5),
            weekEnding: weekEnding,
            calendar: calendar
        )
        XCTAssertEqual(summary.highLoadStreakDays, 5)
        // 0.85 - 5*0.05 = 0.60
        XCTAssertEqual(summary.equilibriumScore, 0.60, accuracy: 0.0001)
    }

    func testMaxConsecutiveHighLoadDaysWithinWeek() {
        let bounds = WeeklyReviewAggregator.weekBounds(ending: weekEnding, calendar: calendar)
        var tasks: [LifeTask] = []
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: bounds.start) else { continue }
            let isHighLoad = (2...4).contains(offset)
            let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
            tasks.append(
                LifeTask(
                    title: "Block \(offset)",
                    status: .completed,
                    estimatedMinutes: 120,
                    scheduledDate: day,
                    scheduledTime: start,
                    timeConstraint: .anchored,
                    userId: "u"
                )
            )
            if !isHighLoad {
                tasks.append(
                    LifeTask(
                        title: "Fluid \(offset)",
                        status: .completed,
                        estimatedMinutes: 60,
                        scheduledDate: day,
                        scheduledTime: start,
                        timeConstraint: .fluid,
                        userId: "u"
                    )
                )
            }
        }

        let streak = HighLoadDayEvaluator.maxConsecutiveHighLoadDays(
            inWeekEnding: weekEnding,
            tasks: tasks,
            calendar: calendar
        )
        XCTAssertEqual(streak, 3)
    }

    func testRecordBuilderMapsDecisions() {
        let decisions = [
            ConflictCascadeDecision(taskID: "a", action: .shiftLater, reason: "clash", shiftMinutes: 45),
            ConflictCascadeDecision(taskID: "b", action: .superseded, reason: "dup"),
            ConflictCascadeDecision(taskID: "c", action: .keep, reason: "winner")
        ]
        let records = CascadeActionRecordBuilder.records(
            from: decisions,
            triggeredRecoveryLock: true,
            recoveryDurationMinutes: 90,
            now: weekEnding
        )
        XCTAssertEqual(records.filter { $0.kind == .sabotageAuction }.count, 1)
        XCTAssertEqual(records.filter { $0.kind == .shiftedLater }.first?.durationMinutes, 45)
        XCTAssertEqual(records.filter { $0.kind == .superseded }.count, 1)
        XCTAssertFalse(records.contains { $0.kind == .other })
        XCTAssertEqual(records.count, 3) // sabotage + shift + superseded (keep dropped)
    }

    func testCascadeActionLogHistoryRoundTrip() {
        let log = CascadeActionLog.inMemory()
        let t = weekEnding.addingTimeInterval(-86_400)
        log.appendHistory([
            CascadeActionRecord(kind: .expired, timestamp: t, durationMinutes: 0, taskID: "x")
        ], now: weekEnding, calendar: calendar)
        XCTAssertEqual(log.historyRecords().count, 1)
        XCTAssertEqual(log.historyRecords(weekEnding: weekEnding, calendar: calendar).count, 1)
        log.clear()
        XCTAssertTrue(log.historyRecords().isEmpty)
    }
}
