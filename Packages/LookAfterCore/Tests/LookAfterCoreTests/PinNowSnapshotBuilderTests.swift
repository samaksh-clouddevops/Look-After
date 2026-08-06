import XCTest
@testable import LookAfterCore

final class PinNowSnapshotBuilderTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private var day: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 6, hour: 0, minute: 0))!
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 6, hour: 10, minute: 0))!
    }

    func testBuildUsesHeroTaskHeadlineAndPredictionContext() {
        let task = LifeTask(
            id: "t1",
            title: "Write quarterly report",
            priority: .high,
            estimatedMinutes: 45,
            scheduledTime: Date(),
            userId: "test-user"
        )
        let prediction = FlowPrediction(
            taskID: "t1",
            suggestedDurationMinutes: 40,
            buttonLabel: "Start",
            buttonSubtitle: "Strong focus window",
            confidence: 0.9,
            reasoning: "Your energy is high — good time for deep work.",
            actionType: .start
        )
        let surface = FlowSurface(
            heroTask: task,
            prediction: prediction,
            energyScore: 0.82
        )
        let cognitive = CognitiveSnapshot(
            energy: .high,
            energyScore: 0.82
        )

        let model = PinNowSnapshotBuilder.build(
            tasks: [task],
            flowSurface: surface,
            cognitiveSnapshot: cognitive
        )

        XCTAssertNotNil(model)
        XCTAssertEqual(model?.headline, "Write quarterly report")
        XCTAssertEqual(model?.estimatedMinutes, 40)
        XCTAssertEqual(model?.energyScore, 82)
        XCTAssertEqual(model?.energyLevel, EnergyLevel.high.rawValue)
        XCTAssertTrue(model?.contextLine.contains("energy") ?? false)
        XCTAssertFalse(model?.categoryIcon.isEmpty ?? true)
    }

    func testFlowHeroWinsOverLifeCommitmentExecutionBlock() {
        let workStart = calendar.date(from: DateComponents(year: 2026, month: 8, day: 6, hour: 9, minute: 0))!
        let workEnd = calendar.date(from: DateComponents(year: 2026, month: 8, day: 6, hour: 13, minute: 30))!
        let gymStart = calendar.date(from: DateComponents(year: 2026, month: 8, day: 6, hour: 8, minute: 0))!
        let gymEnd = calendar.date(from: DateComponents(year: 2026, month: 8, day: 6, hour: 9, minute: 30))!

        let work = LifeTask(
            id: "work",
            title: "Work",
            lifeArea: .work,
            priority: .high,
            estimatedMinutes: 270,
            scheduledDate: day,
            scheduledTime: workStart,
            timeConstraint: .anchored,
            scheduledEndTime: workEnd,
            userId: "test-user"
        )

        let gym = LifeTask(
            id: "gym",
            title: "Gym",
            description: "Life commitment from your profile",
            lifeArea: .health,
            estimatedMinutes: 90,
            scheduledDate: day,
            scheduledTime: gymStart,
            tags: [LifeModel.commitmentTaskTag],
            scheduledEndTime: gymEnd,
            userId: "test-user"
        )

        let surface = FlowSurface(heroTask: work)

        let model = PinNowSnapshotBuilder.build(
            tasks: [work, gym],
            flowSurface: surface,
            cognitiveSnapshot: nil,
            preferredTask: work,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(model?.headline, "Work")
        XCTAssertEqual(model?.constraintLabel, "Anchored")
    }

    func testAnchoredWorkWinsOverlappingLifeCommitmentInExecutionResolver() {
        let workStart = calendar.date(from: DateComponents(year: 2026, month: 8, day: 6, hour: 9, minute: 0))!
        let workEnd = calendar.date(from: DateComponents(year: 2026, month: 8, day: 6, hour: 13, minute: 30))!
        let gymStart = calendar.date(from: DateComponents(year: 2026, month: 8, day: 6, hour: 8, minute: 0))!
        let gymEnd = calendar.date(from: DateComponents(year: 2026, month: 8, day: 6, hour: 11, minute: 0))!

        let work = LifeTask(
            id: "work",
            title: "Work",
            lifeArea: .work,
            priority: .high,
            estimatedMinutes: 270,
            scheduledDate: day,
            scheduledTime: workStart,
            timeConstraint: .anchored,
            scheduledEndTime: workEnd,
            userId: "test-user"
        )

        let gym = LifeTask(
            id: "gym",
            title: "Gym",
            lifeArea: .health,
            estimatedMinutes: 90,
            scheduledDate: day,
            scheduledTime: gymStart,
            tags: [LifeModel.commitmentTaskTag],
            scheduledEndTime: gymEnd,
            userId: "test-user"
        )

        let snapshot = ExecutionBlockResolver.resolve(tasks: [work, gym], now: now, calendar: calendar)
        XCTAssertEqual(snapshot.taskID, "work")
        XCTAssertEqual(snapshot.taskTitle, "Work")
    }

    func testCompactDurationFormatsLongBlocks() {
        XCTAssertEqual(PinNowSnapshotBuilder.compactDuration(minutes: 270), "4h 30m")
        XCTAssertEqual(PinNowSnapshotBuilder.compactDuration(minutes: 120), "2h")
        XCTAssertEqual(PinNowSnapshotBuilder.compactDuration(minutes: 45), "45m")
    }

    func testTimelineNowWinsOverHeroAndExecution() {
        let workStart = calendar.date(from: DateComponents(year: 2026, month: 8, day: 6, hour: 9, minute: 0))!
        let workEnd = calendar.date(from: DateComponents(year: 2026, month: 8, day: 6, hour: 13, minute: 30))!
        let gymStart = calendar.date(from: DateComponents(year: 2026, month: 8, day: 6, hour: 8, minute: 0))!
        let gymEnd = calendar.date(from: DateComponents(year: 2026, month: 8, day: 6, hour: 9, minute: 30))!

        let work = LifeTask(
            id: "work",
            title: "Work",
            lifeArea: .work,
            priority: .high,
            estimatedMinutes: 270,
            scheduledDate: day,
            scheduledTime: workStart,
            timeConstraint: .anchored,
            scheduledEndTime: workEnd,
            userId: "test-user"
        )

        let gym = LifeTask(
            id: "gym",
            title: "Gym",
            lifeArea: .health,
            estimatedMinutes: 90,
            scheduledDate: day,
            scheduledTime: gymStart,
            tags: [LifeModel.commitmentTaskTag],
            scheduledEndTime: gymEnd,
            userId: "test-user"
        )

        let timelineEvents = [
            LifeTimelineEvent(
                id: "task-gym",
                kind: .exercise,
                title: "Gym",
                subtitle: "Planned",
                date: gymStart,
                estimatedMinutes: 90
            ),
            LifeTimelineEvent(
                id: "task-work",
                kind: .work,
                title: "Work",
                subtitle: "Planned",
                date: workStart,
                estimatedMinutes: 270,
                timeConstraint: .anchored
            ),
        ]

        let nowEvent = TimelineNowResolver.currentNowEvent(in: timelineEvents, now: now, calendar: calendar)
        XCTAssertEqual(nowEvent?.title, "Work")

        let surface = FlowSurface(heroTask: gym)

        let model = PinNowSnapshotBuilder.build(
            tasks: [work, gym],
            flowSurface: surface,
            cognitiveSnapshot: nil,
            preferredTask: gym,
            timelineEvents: timelineEvents,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(model?.headline, "Work")
        XCTAssertEqual(model?.sectionLabel, "NOW")
        XCTAssertEqual(model?.constraintLabel, "Anchored")
    }

    func testBuildReturnsNilWhenNoActiveTasks() {
        let model = PinNowSnapshotBuilder.build(
            tasks: [],
            flowSurface: nil,
            cognitiveSnapshot: nil
        )
        XCTAssertNil(model)
    }
}
