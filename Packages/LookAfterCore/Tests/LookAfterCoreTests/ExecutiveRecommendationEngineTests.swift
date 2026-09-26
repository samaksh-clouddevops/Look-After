import XCTest
@testable import LookAfterCore

final class ExecutiveRecommendationEngineTests: XCTestCase {

    private var evening: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 1
        components.hour = 21
        components.minute = 52
        return Calendar.current.date(from: components)!
    }

    func testEveningStaleMorningWorkFallsBackToEveningPlan() {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 2
        components.hour = 23
        let lateEvening = Calendar.current.date(from: components)!

        let dayStart = Calendar.current.startOfDay(for: lateEvening)
        let workStart = Calendar.current.date(bySettingHour: 8, minute: 30, second: 0, of: dayStart)!
        let work = LifeTask(
            title: "Work",
            lifeArea: .work,
            estimatedMinutes: 51,
            scheduledDate: dayStart,
            scheduledTime: workStart,
            schedulingMode: .fixedTime
        )
        let musicStart = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: dayStart)!
        let musicEnd = Calendar.current.date(bySettingHour: 23, minute: 30, second: 0, of: dayStart)!
        let music = LifeTask(
            title: "Music production",
            lifeArea: .creativity,
            estimatedMinutes: 90,
            scheduledDate: dayStart,
            scheduledTime: musicStart,
            schedulingMode: .fixedTime,
            scheduledEndTime: musicEnd
        )

        let snapshot = LifeContextSnapshot(currentEnergy: 0.6, availableTimeMinutes: 90, currentMission: work)
        let output = ExecutiveRecommendationEngine.recommend(from: ExecutiveRecommendationEngine.Input(
            task: work,
            snapshot: snapshot,
            tasks: [work, music],
            now: lateEvening
        ))

        XCTAssertNotNil(output)
        XCTAssertEqual(output?.taskID, music.id)
    }

    func testVirtualMorningDoesNotHeroWallClockOverdueTask() {
        var morningParts = DateComponents()
        morningParts.year = 2026
        morningParts.month = 8
        morningParts.day = 1
        morningParts.hour = 9
        let virtualMorning = Calendar.current.date(from: morningParts)!

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let wallClockOverdue = LifeTask(
            id: "wall",
            title: "Wall clock leftover",
            priority: .high,
            estimatedMinutes: 20,
            scheduledDate: Calendar.current.startOfDay(for: yesterday)
        )
        let virtualDay = Calendar.current.startOfDay(for: virtualMorning)
        let virtualDayTask = LifeTask(
            id: "virtual",
            title: "Virtual day review",
            priority: .low,
            estimatedMinutes: 20,
            scheduledDate: virtualDay
        )

        XCTAssertTrue(wallClockOverdue.isOverdue, "Precondition: leftover is overdue on the wall clock")
        XCTAssertFalse(
            wallClockOverdue.isOverdue(calendar: .current, referenceDate: virtualMorning),
            "The same leftover is still in the future on the virtual morning"
        )

        let briefing = ContextBriefingGenerator().generate(
            from: LifeContextSnapshot(currentEnergy: 0.7, availableTimeMinutes: 90),
            resume: nil,
            now: virtualMorning,
            context: ContextBriefingGenerator.GenerationContext(tasks: [wallClockOverdue, virtualDayTask])
        )

        XCTAssertEqual(briefing.hero.action.taskID, virtualDayTask.id)
    }

    func testHeroDoesNotStealFutureDatedOneOffWithPastDeadline() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 9))!
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let futureDated = LifeTask(
            id: "friday",
            title: "Friday review",
            priority: .high,
            estimatedMinutes: 20,
            deadline: yesterday,
            scheduledDate: tomorrow
        )
        let todayTask = LifeTask(
            id: "today",
            title: "Today's work",
            priority: .low,
            estimatedMinutes: 20,
            scheduledDate: today
        )

        XCTAssertTrue(futureDated.isOverdue(calendar: calendar, referenceDate: now))
        XCTAssertFalse(futureDated.isActionableToday(allTasks: [futureDated, todayTask], calendar: calendar, referenceDate: now))

        let briefing = ContextBriefingGenerator(calendar: calendar).generate(
            from: LifeContextSnapshot(currentEnergy: 0.7, availableTimeMinutes: 90),
            resume: nil,
            now: now,
            context: ContextBriefingGenerator.GenerationContext(tasks: [futureDated, todayTask])
        )

        XCTAssertEqual(briefing.hero.action.taskID, todayTask.id)
    }

    func testHeroDoesNotStealLeftoverRecurringOccurrence() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 9))!
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let leftover = LifeTask(
            id: "leftover",
            title: "Daily standup",
            priority: .high,
            estimatedMinutes: 15,
            scheduledDate: yesterday,
            recurrence: .daily,
            parentTaskId: "template"
        )
        let todayTask = LifeTask(
            id: "today",
            title: "Write notes",
            priority: .low,
            estimatedMinutes: 20,
            scheduledDate: today
        )

        XCTAssertTrue(leftover.isOverdue(calendar: calendar, referenceDate: now))
        XCTAssertFalse(leftover.isOverdueOneOffCarryForward(calendar: calendar, referenceDate: now))
        XCTAssertFalse(leftover.isActionableToday(allTasks: [leftover, todayTask], calendar: calendar, referenceDate: now))

        let briefing = ContextBriefingGenerator(calendar: calendar).generate(
            from: LifeContextSnapshot(currentEnergy: 0.7, availableTimeMinutes: 90),
            resume: nil,
            now: now,
            context: ContextBriefingGenerator.GenerationContext(tasks: [leftover, todayTask])
        )

        XCTAssertEqual(briefing.hero.action.taskID, todayTask.id)
    }

    func testEveningThyroidMedicationSkipsToAlternateOrEveningPlan() {
        let thyroid = LifeTask(
            title: "Take Thyroid Medication",
            steps: [TaskStep(title: "Walk to where your thyroid medication is kept", isCompleted: false)],
            estimatedMinutes: 5,
            semanticProfile: TaskSemanticProfileBuilder.build(from: LifeTask(
                title: "Take levothyroxine",
                description: "Morning thyroid medication before breakfast"
            ))
        )
        let work = LifeTask(
            title: "Deep Work Block 1",
            description: "Review Azure deployment",
            estimatedMinutes: 30,
            semanticProfile: TaskSemanticProfile(semanticType: .deepWork)
        )

        let snapshot = LifeContextSnapshot(currentEnergy: 0.6, availableTimeMinutes: 90)
        let output = ExecutiveRecommendationEngine.recommend(from: ExecutiveRecommendationEngine.Input(
            task: thyroid,
            snapshot: snapshot,
            tasks: [thyroid, work],
            now: evening
        ))

        XCTAssertNotNil(output)
        XCTAssertFalse(output?.headline.lowercased().contains("walk to") == true)
        XCTAssertFalse(output?.headline.lowercased().contains("missed") == true)
    }

    func testGymPrepRecommendationBeforeSession() {
        var gymTime = evening
        gymTime = Calendar.current.date(byAdding: .minute, value: 25, to: evening)!

        let task = LifeTask(
            title: "Gym",
            estimatedMinutes: 60,
            scheduledTime: gymTime,
            semanticProfile: TaskSemanticProfile(semanticType: .physicalActivity)
        )

        let snapshot = LifeContextSnapshot(currentEnergy: 0.7, availableTimeMinutes: 120)
        let output = ExecutiveRecommendationEngine.recommend(from: ExecutiveRecommendationEngine.Input(
            task: task,
            snapshot: snapshot,
            now: evening
        ))

        XCTAssertTrue(
            output?.headline == "Put on workout clothes" || output?.headline == "Fill your water bottle",
            "Expected prep headline, got \(output?.headline ?? "nil")"
        )
        XCTAssertEqual(output?.buttonLabel, "I'm ready")
        XCTAssertTrue(output?.isPreparation == true)
    }

    func testHeadlineAndButtonAreDistinct() {
        let task = LifeTask(
            title: "Deep Work Block 1",
            description: "Review Azure deployment",
            estimatedMinutes: 30,
            semanticProfile: TaskSemanticProfile(semanticType: .deepWork)
        )
        let snapshot = LifeContextSnapshot(currentEnergy: 0.75, availableTimeMinutes: 120)
        let output = ExecutiveRecommendationEngine.recommend(from: ExecutiveRecommendationEngine.Input(
            task: task,
            snapshot: snapshot,
            now: evening
        ))

        XCTAssertEqual(output?.headline, "Review Azure deployment")
        XCTAssertEqual(output?.buttonLabel, "Start now")
        XCTAssertNotEqual(output?.headline, output?.buttonLabel)
    }

    func testMedicationStepNotUsedAsObjective() {
        let task = LifeTask(
            title: "Thyroid medication",
            description: "Take levothyroxine on empty stomach",
            steps: [TaskStep(title: "Walk to where your thyroid medication is kept", isCompleted: false)],
            semanticProfile: TaskSemanticProfile(semanticType: .medication, subtype: "Morning fasting medication")
        )
        let context = HeroObjectiveContextBuilder.from(task: task)
        let headline = HeroObjectiveResolver.resolveHeadline(from: context)

        XCTAssertFalse(headline.lowercased().contains("walk to"))
        XCTAssertTrue(headline.lowercased().contains("levothyroxine") || headline.lowercased().contains("medication"))
    }
}
