import XCTest
@testable import LookAfterCore

final class DayAuditServiceTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func testEmptyDayHasNoBlockingQuestions() {
        let now = makeDate(hour: 9)
        let result = DayAuditService.run(
            DayAuditService.Input(
                tasks: [],
                energyPercent: 60,
                capacityBandLabel: "Steady",
                referenceDate: now,
                now: now,
                calendar: calendar
            )
        )
        XCTAssertTrue(result.clarifyingQuestions.isEmpty)
        XCTAssertFalse(result.capacitySummary.isOverloaded)
    }

    func testOvercommitProducesShrinkOrSkipFixes() {
        let now = makeDate(hour: 9)
        let day = calendar.startOfDay(for: now)
        let meetingStart = makeDate(hour: 10)
        let meeting = LifeTask(
            id: "meeting",
            title: "Standup",
            estimatedMinutes: 30,
            scheduledDate: day,
            scheduledTime: meetingStart,
            schedulingMode: .fixedTime,
            timeConstraint: .anchored,
            scheduledEndTime: makeDate(hour: 10, minute: 30)
        )
        let flexA = LifeTask(
            id: "a",
            title: "Deep work A",
            priority: .high,
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: now,
            schedulingMode: .flexible,
            timeConstraint: .flexible
        )
        let flexB = LifeTask(
            id: "b",
            title: "Deep work B",
            priority: .medium,
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: now.addingTimeInterval(60),
            schedulingMode: .flexible,
            timeConstraint: .flexible
        )

        let result = DayAuditService.run(
            DayAuditService.Input(
                tasks: [meeting, flexA, flexB],
                energyPercent: 55,
                capacityBandLabel: "Steady",
                referenceDate: now,
                now: now,
                calendar: calendar
            )
        )

        XCTAssertTrue(result.faults.contains(where: { $0.sourceKind == DayAuditFault.SourceKind.preWindowFit }))
        XCTAssertFalse(result.proposedFixes.isEmpty)
    }

    func testParkedCandidatesAppearInPossiblePullsWhenGapExists() {
        let now = makeDate(hour: 14)
        let parked = ParkedTaskEntry(
            taskID: "parked-1",
            title: "Call dentist",
            originalDurationMinutes: 20,
            priority: .medium,
            lifeArea: .personal
        )
        let result = DayAuditService.run(
            DayAuditService.Input(
                tasks: [],
                parkedCandidates: [parked],
                energyPercent: 70,
                capacityBandLabel: "Open",
                referenceDate: now,
                now: now,
                calendar: calendar,
                maxPulls: 3
            )
        )
        XCTAssertTrue(result.possiblePulls.contains(where: { $0.taskID == "parked-1" }))
    }

    func testQuestionsCappedAtTwo() {
        let now = makeDate(year: 2026, month: 8, day: 8, hour: 10) // Saturday
        let work = LifeTask(
            id: "work-1",
            title: "Quarterly report",
            lifeArea: .work,
            estimatedMinutes: 120,
            scheduledDate: calendar.startOfDay(for: now),
            scheduledTime: now,
            schedulingMode: .flexible,
            timeConstraint: .flexible
        )
        let result = DayAuditService.run(
            DayAuditService.Input(
                tasks: [work],
                energyPercent: 25,
                capacityBandLabel: "Low",
                referenceDate: now,
                now: now,
                calendar: calendar,
                maxQuestions: 2
            )
        )
        XCTAssertLessThanOrEqual(result.clarifyingQuestions.count, 2)
    }

    func testSummaryLinesPreferCapacityAndFaults() {
        let summary = DayAuditCapacitySummary(
            bandLabel: "Steady",
            energyPercent: 50,
            bookedFlexMinutes: 200,
            remainingFlexMinutes: 0,
            isOverloaded: true
        )
        let result = DayAuditResult(
            faults: [
                DayAuditFault(severity: .high, message: "Too much flex before standup.", sourceKind: .preWindowFit)
            ],
            capacitySummary: summary,
            clarifyingQuestions: [
                DayAuditQuestion(prompt: "Keep deep work?", options: ["Yes", "No"])
            ]
        )
        XCTAssertFalse(result.summaryLines.isEmpty)
        XCTAssertTrue(result.hasBlockingQuestions)
        XCTAssertTrue(result.hasMaterialFindings)
    }

    private func makeDate(
        year: Int = 2026,
        month: Int = 8,
        day: Int = 4,
        hour: Int,
        minute: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
