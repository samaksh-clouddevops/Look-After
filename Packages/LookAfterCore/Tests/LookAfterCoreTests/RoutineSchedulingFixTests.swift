import XCTest
@testable import LookAfterCore

final class TaskScheduleQueryTests: XCTestCase {

    func testSupersededDuplicateIDsPreferScheduledOccurrence() {
        let day = Calendar.current.startOfDay(for: Date())
        let templateId = "template-1"
        var parked = LifeTask(
            id: "parked-1",
            title: "Brush teeth — evening",
            schedulingMode: .flexible,
            userId: "user-1"
        )
        parked.parentTaskId = templateId
        var occurrence = LifeTask(
            id: "occ-1",
            title: "Brush teeth — evening",
            scheduledDate: day,
            scheduledTime: Calendar.current.date(bySettingHour: 21, minute: 30, second: 0, of: day),
            schedulingMode: .fixedTime,
            userId: "user-1"
        )
        occurrence.parentTaskId = templateId

        let stale = TaskScheduleQuery.supersededDuplicateIDs(in: [parked, occurrence], on: day)
        XCTAssertEqual(stale, ["parked-1"])
    }

    func testEphemeralityEnrichAddsMealSemantics() {
        let task = LifeTask(
            title: "Breakfast",
            tags: ["daily-routine", "onboarding"],
            recurrence: .daily,
            userId: "user-1"
        )

        let enriched = TaskEphemeralityDefaults.enrich(task)
        XCTAssertEqual(enriched.expirationPolicy, .endOfDay)
        XCTAssertEqual(enriched.collisionStrategy, .dropOldest)
        XCTAssertEqual(enriched.semanticProfile?.semanticType, .errand)
        XCTAssertEqual(enriched.semanticProfile?.subtype, "meal")
    }

    func testSeriesKeyUsesNormalizedTitleForDifferentTemplateIDs() {
        let day = Calendar.current.startOfDay(for: Date())
        var occurrence1 = LifeTask(
            id: "occ-1",
            title: "Dinner",
            scheduledDate: day,
            userId: "user-1"
        )
        occurrence1.parentTaskId = "template-a"
        var occurrence2 = LifeTask(
            id: "occ-2",
            title: "Dinner",
            scheduledDate: day,
            userId: "user-1"
        )
        occurrence2.parentTaskId = "template-b"

        XCTAssertEqual(TaskScheduleQuery.seriesKey(for: occurrence1), TaskScheduleQuery.seriesKey(for: occurrence2))
        XCTAssertEqual(TaskScheduleQuery.seriesKey(for: occurrence1), "recurring|dinner")
    }

    func testDedupeDuplicateRecurrenceTemplatesMergesOccurrences() {
        let day = makeDate(year: 2026, month: 8, day: 5)
        var template1 = LifeTask(
            id: "tmpl-a",
            title: "Dinner",
            tags: ["daily-routine"],
            recurrence: .daily,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        template1.createdAt = makeDate(year: 2026, month: 1, day: 1)
        var template2 = LifeTask(
            id: "tmpl-b",
            title: "Dinner",
            recurrence: .daily,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        template2.createdAt = makeDate(year: 2026, month: 2, day: 1)
        var occurrence1 = LifeTask(
            id: "occ-a",
            title: "Dinner",
            status: .pending,
            scheduledDate: day,
            parentTaskId: template1.id,
            userId: "user-1"
        )
        var occurrence2 = LifeTask(
            id: "occ-b",
            title: "Dinner",
            status: .pending,
            scheduledDate: day,
            parentTaskId: template2.id,
            userId: "user-1"
        )

        let plan = TaskRecurrenceEngine.dedupeDuplicateRecurrenceTemplates(
            in: [template1, template2, occurrence1, occurrence2],
            calendar: calendar,
            referenceDate: day
        )

        XCTAssertEqual(Set(plan.templateIDsToDelete), ["tmpl-b"])
        XCTAssertEqual(plan.occurrenceUpdates.count, 1)
        XCTAssertEqual(plan.occurrenceUpdates.first?.id, "occ-b")
        XCTAssertEqual(plan.occurrenceUpdates.first?.parentTaskId, "tmpl-a")
    }

    func testStandaloneDinnerSupersededWhenRecurringOccurrenceExists() {
        let day = makeDate(year: 2026, month: 8, day: 5)
        var template = LifeTask(
            id: "tmpl-dinner",
            title: "Dinner",
            recurrence: .daily,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        template.createdAt = makeDate(year: 2026, month: 1, day: 1)
        let occurrence = LifeTask(
            id: "occ-dinner",
            title: "Dinner",
            status: .pending,
            scheduledDate: day,
            parentTaskId: template.id,
            userId: "user-1"
        )
        let standalone = LifeTask(
            id: "standalone-dinner",
            title: "Dinner",
            status: .pending,
            scheduledDate: day,
            schedulingMode: .fixedTime,
            userId: "user-1"
        )

        let invalid = TaskRecurrenceEngine.invalidScheduledTaskIDs(
            in: [template, occurrence, standalone],
            calendar: calendar
        )
        XCTAssertEqual(invalid, ["standalone-dinner"])
    }

    func testCompletedLifeCommitmentGymSuppressesRecurringOccurrenceToday() {
        let day = makeDate(year: 2026, month: 8, day: 7)
        let gymStart = makeDate(year: 2026, month: 8, day: 7, hour: 18, minute: 30)
        let gymEnd = makeDate(year: 2026, month: 8, day: 7, hour: 20, minute: 0)
        var commitment = LifeTask(
            id: "gym-commitment",
            title: "Gym",
            status: .completed,
            scheduledDate: day,
            scheduledTime: gymStart,
            tags: [LifeModel.commitmentTaskTag, "life-commitment:gym"],
            schedulingMode: .fixedTime,
            scheduledEndTime: gymEnd,
            userId: "user-1"
        )
        commitment.completedAt = makeDate(year: 2026, month: 8, day: 7, hour: 20, minute: 27)

        let template = LifeTask(
            id: "gym-template",
            title: "Gym",
            status: .pending,
            tags: ["daily-routine", "onboarding"],
            recurrence: .daily,
            userId: "user-1",
            isRecurrenceTemplate: true
        )

        let all = [commitment, template]
        XCTAssertTrue(TaskRecurrenceEngine.fulfilledSeriesKeys(on: day, in: all, calendar: calendar).contains("recurring|gym"))
        XCTAssertTrue(TaskRecurrenceEngine.missingOccurrences(for: all, on: day, calendar: calendar).isEmpty)
        XCTAssertTrue(TaskRecurrenceEngine.timelineProjections(for: all, on: day, calendar: calendar).isEmpty)
        XCTAssertTrue(
            TaskRecurrenceEngine.recurringDuplicateIDsOfLifeCommitments(
                in: all,
                calendar: calendar,
                referenceDate: day
            ).contains("gym-template")
        )
    }

    func testCompletedRecurringGymSuppressesActiveLifeCommitmentDuplicate() {
        let day = makeDate(year: 2026, month: 8, day: 7)
        let gymStart = makeDate(year: 2026, month: 8, day: 7, hour: 20, minute: 27)
        var occurrence = LifeTask(
            id: "gym-occurrence",
            title: "Gym",
            status: .completed,
            scheduledDate: day,
            scheduledTime: gymStart,
            tags: ["daily-routine"],
            userId: "user-1"
        )
        occurrence.parentTaskId = "gym-template"
        occurrence.completedAt = gymStart

        let commitment = LifeTask(
            id: "gym-commitment",
            title: "Gym",
            status: .pending,
            scheduledDate: day,
            scheduledTime: makeDate(year: 2026, month: 8, day: 7, hour: 18, minute: 30),
            tags: [LifeModel.commitmentTaskTag, "life-commitment:gym"],
            schedulingMode: .fixedTime,
            scheduledEndTime: makeDate(year: 2026, month: 8, day: 7, hour: 20, minute: 0),
            userId: "user-1"
        )

        let duplicates = TaskRecurrenceEngine.duplicateActiveSeriesIDs(
            afterCompleting: occurrence,
            in: [occurrence, commitment],
            calendar: calendar
        )
        XCTAssertTrue(duplicates.contains("gym-commitment"))
    }

    func testFulfilledSeriesRemovesTimelineProjection() {
        let day = makeDate(year: 2026, month: 8, day: 7)
        var completed = LifeTask(
            id: "gym-done",
            title: "Gym",
            status: .completed,
            scheduledDate: day,
            tags: [LifeModel.commitmentTaskTag],
            userId: "user-1"
        )
        completed.completedAt = makeDate(year: 2026, month: 8, day: 7, hour: 20, minute: 0)
        let template = LifeTask(
            id: "gym-template",
            title: "Gym",
            recurrence: .daily,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        let all = [completed, template]
        let timeline = TaskScheduleQuery.tasksForDay(from: [], allTasks: all, day: day, calendar: calendar)
        XCTAssertTrue(timeline.isEmpty)
    }

    func testFulfilledSeriesTodayDoesNotSupersedeTomorrowOccurrence() {
        let today = makeDate(year: 2026, month: 8, day: 7)
        let tomorrow = makeDate(year: 2026, month: 8, day: 8)
        var completed = LifeTask(
            id: "dinner-done",
            title: "Dinner",
            status: .completed,
            scheduledDate: today,
            userId: "user-1"
        )
        completed.completedAt = makeDate(year: 2026, month: 8, day: 7, hour: 19, minute: 15)

        let tomorrowOccurrence = LifeTask(
            id: "dinner-tomorrow",
            title: "Dinner",
            status: .pending,
            scheduledDate: tomorrow,
            parentTaskId: "dinner-template",
            userId: "user-1"
        )

        let all = [completed, tomorrowOccurrence]
        let staleToday = TaskSeriesResolver.staleActiveSeriesIDs(in: all, on: today, calendar: calendar)
        XCTAssertFalse(staleToday.contains("dinner-tomorrow"))
    }

    func testCompletedTaskWithoutSlotUsesCompletedAtOnTimeline() {
        let now = makeDate(year: 2026, month: 8, day: 7, hour: 22, minute: 0)
        let day = calendar.startOfDay(for: now)
        var completed = LifeTask(
            title: "Dinner",
            status: .completed,
            scheduledDate: day,
            userId: "user-1"
        )
        completed.completedAt = makeDate(year: 2026, month: 8, day: 7, hour: 19, minute: 10)

        let events = LifeTimelinePresenter.build(
            tasks: [],
            completedToday: [completed],
            bills: [],
            shoppingItems: [],
            contacts: [],
            now: now,
            calendar: calendar
        )

        let event = events.first(where: { $0.title == "Dinner" })
        XCTAssertNotNil(event)
        XCTAssertEqual(calendar.component(.hour, from: event!.date), 19)
        XCTAssertFalse(event!.subtitle.contains("12:00 AM"))
    }

    func testCompletedTaskWithoutCompletedAtUsesUpdatedAtOnTimeline() {
        let now = makeDate(year: 2026, month: 8, day: 7, hour: 22, minute: 0)
        let day = calendar.startOfDay(for: now)
        var completed = LifeTask(
            title: "Dinner",
            status: .completed,
            scheduledDate: day,
            userId: "user-1"
        )
        completed.updatedAt = makeDate(year: 2026, month: 8, day: 7, hour: 20, minute: 5)

        let events = LifeTimelinePresenter.build(
            tasks: [],
            completedToday: [completed],
            bills: [],
            shoppingItems: [],
            contacts: [],
            now: now,
            calendar: calendar
        )

        let event = events.first(where: { $0.title == "Dinner" })
        XCTAssertNotNil(event)
        XCTAssertEqual(calendar.component(.hour, from: event!.date), 20)
    }

    func testKeeperPrefersAnchoredOccurrenceOverMidnightPlaceholder() {
        let day = makeDate(year: 2026, month: 8, day: 7)
        let midnight = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: day)!
        let evening = makeDate(year: 2026, month: 8, day: 7, hour: 19, minute: 0)
        let midnightOccurrence = LifeTask(
            id: "dinner-midnight",
            title: "Dinner",
            status: .pending,
            scheduledDate: day,
            scheduledTime: midnight,
            parentTaskId: "dinner-template",
            userId: "user-1"
        )
        let anchoredOccurrence = LifeTask(
            id: "dinner-evening",
            title: "Dinner",
            status: .pending,
            scheduledDate: day,
            scheduledTime: evening,
            parentTaskId: "dinner-template",
            scheduledEndTime: calendar.date(byAdding: .minute, value: 45, to: evening),
            userId: "user-1"
        )

        let keeper = TaskScheduleQuery.preferredKeeper(
            in: [midnightOccurrence, anchoredOccurrence],
            on: day,
            calendar: calendar
        )
        XCTAssertEqual(keeper?.id, "dinner-evening")
    }

    private let calendar = Calendar(identifier: .gregorian)

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}

final class LifeTimelineKindResolverTests: XCTestCase {

    func testBrushTeethAlwaysHabitEvenWithPersonalLifeArea() {
        let task = LifeTask(
            title: "Brush teeth — evening",
            lifeArea: .personal,
            tags: ["daily-routine"],
            userId: "user-1"
        )
        XCTAssertEqual(LifeTimelineKindResolver.kind(for: task), .habit)
    }

    func testBrushTeethNotRecoveryWithStoredGenericProfile() {
        var task = LifeTask(
            title: "Brush teeth — morning",
            lifeArea: .personal,
            tags: ["daily-routine"],
            userId: "user-1"
        )
        task.semanticProfile = TaskSemanticProfile(semanticType: .generic, subtype: "misc")
        XCTAssertEqual(LifeTimelineKindResolver.kind(for: task), .habit)
    }

    func testBreakfastMapsToHealthNotShopping() {
        let task = LifeTask(
            title: "Breakfast",
            lifeArea: .health,
            tags: ["daily-routine"],
            recurrence: .daily,
            userId: "user-1"
        )
        XCTAssertEqual(LifeTimelineKindResolver.kind(for: task), .health)
    }

    func testSleepBoundaryStaysRecovery() {
        let task = LifeTask(title: "Wind down · Sleep", lifeArea: .health, userId: "user-1")
        XCTAssertEqual(LifeTimelineKindResolver.kind(for: task), .health)
    }
}
