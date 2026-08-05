import XCTest
@testable import LookAfterCore

final class DayScheduleReconcilerTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testGymOverlapPushesDinnerLater() {
        let day = makeDate(year: 2026, month: 8, day: 4)
        let gymStart = makeDate(year: 2026, month: 8, day: 4, hour: 18, minute: 30)
        let gymEnd = makeDate(year: 2026, month: 8, day: 4, hour: 20, minute: 0)
        let dinnerStart = makeDate(year: 2026, month: 8, day: 4, hour: 19, minute: 0)
        let dinnerEnd = makeDate(year: 2026, month: 8, day: 4, hour: 19, minute: 45)

        let gym = LifeTask(
            title: "Gym",
            estimatedMinutes: 90,
            scheduledDate: day,
            scheduledTime: gymStart,
            tags: [LifeModel.commitmentTaskTag, "life-commitment:gym"],
            schedulingMode: .fixedTime,
            scheduledEndTime: gymEnd
        )
        var dinner = LifeTask(
            title: "Dinner",
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: dinnerStart,
            tags: ["onboarding", "fixed", "daily-routine"],
            schedulingMode: .fixedTime,
            scheduledEndTime: dinnerEnd
        )
        dinner.priority = .medium

        let result = DayScheduleReconciler.reconcile(
            tasks: [gym, dinner],
            on: day,
            calendar: calendar
        )

        let updatedDinner = result.tasks.first { $0.title == "Dinner" }
        XCTAssertNotNil(updatedDinner)
        let dinnerWindow = TaskScheduleInterval.window(for: updatedDinner!, on: day, calendar: calendar)
        XCTAssertNotNil(dinnerWindow)
        XCTAssertGreaterThanOrEqual(dinnerWindow!.start, gymEnd)
    }

    func testFlexibleTaskMovedAroundFixedGym() {
        let day = makeDate(year: 2026, month: 8, day: 4)
        let gymStart = makeDate(year: 2026, month: 8, day: 4, hour: 18, minute: 30)
        let gymEnd = makeDate(year: 2026, month: 8, day: 4, hour: 20, minute: 0)

        let gym = LifeTask(
            title: "Gym",
            estimatedMinutes: 90,
            scheduledDate: day,
            scheduledTime: gymStart,
            schedulingMode: .fixedTime,
            scheduledEndTime: gymEnd
        )
        let flex = LifeTask(
            title: "Review notes",
            estimatedMinutes: 30,
            scheduledDate: day,
            scheduledTime: makeDate(year: 2026, month: 8, day: 4, hour: 19, minute: 0),
            schedulingMode: .flexible
        )

        let result = DayScheduleReconciler.reconcile(tasks: [gym, flex], on: day, calendar: calendar)
        let updated = result.tasks.first { $0.id == flex.id }
        XCTAssertTrue(result.changedTaskIDs.contains(flex.id))
        let window = TaskScheduleInterval.window(for: updated!, on: day, calendar: calendar)
        XCTAssertGreaterThanOrEqual(window!.start, gymEnd)
    }

    func testSameStartTimeSecondTaskMoves() {
        let day = makeDate(year: 2026, month: 8, day: 4)
        let ninePM = makeDate(year: 2026, month: 8, day: 4, hour: 21, minute: 0)

        let music = LifeTask(
            title: "Music production",
            priority: .high,
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: ninePM,
            tags: [LifeModel.commitmentTaskTag],
            schedulingMode: .fixedTime
        )
        let songwriting = LifeTask(
            title: "Songwriting",
            priority: .medium,
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: ninePM,
            schedulingMode: .flexible
        )

        let result = DayScheduleReconciler.reconcile(tasks: [music, songwriting], on: day, calendar: calendar)
        let updatedSongwriting = result.tasks.first { $0.title == "Songwriting" }
        XCTAssertNotNil(updatedSongwriting)
        let musicWindow = TaskScheduleInterval.window(for: music, on: day, calendar: calendar)
        let songwritingWindow = updatedSongwriting.flatMap {
            TaskScheduleInterval.window(for: $0, on: day, calendar: calendar)
        }
        // Flexible loser may be shifted later, deferred, or parked — but must not keep the
        // same overlapping slot as the fixed commitment.
        if let musicWindow, let songwritingWindow {
            XCTAssertFalse(musicWindow.overlaps(songwritingWindow))
        } else if let updated = updatedSongwriting {
            if let scheduledDate = updated.scheduledDate,
               !calendar.isDate(scheduledDate, inSameDayAs: day) {
                XCTAssertTrue(result.changedTaskIDs.contains(updated.id))
            } else {
                // Parked / unscheduled is a valid cascade outcome.
                XCTAssertNil(updated.scheduledTime)
                XCTAssertTrue(result.changedTaskIDs.contains(updated.id) || updated.timeConstraintValue == .fluid)
            }
        } else {
            XCTFail("Songwriting task missing from reconcile result")
        }
    }

    func testHasOverlapDetectsConflict() {
        let day = makeDate(year: 2026, month: 8, day: 4)
        let gym = LifeTask(
            title: "Gym",
            estimatedMinutes: 90,
            scheduledDate: day,
            scheduledTime: makeDate(year: 2026, month: 8, day: 4, hour: 18, minute: 15),
            schedulingMode: .fixedTime
        )
        let dinner = LifeTask(
            title: "Dinner",
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: makeDate(year: 2026, month: 8, day: 4, hour: 19, minute: 0),
            schedulingMode: .fixedTime
        )
        XCTAssertTrue(DayScheduleReconciler.hasOverlap([gym, dinner], on: day, calendar: calendar))
    }

    func testSyncCommitmentTimesSnapsGymToBlock() {
        let markdown = """
        ### Gym
        **6:30 PM – 8:00 PM**
        """
        let model = LifeModelValidator.compileLocally(from: markdown)
        let day = makeDate(year: 2026, month: 8, day: 4)
        let gym = LifeTask(
            title: "Gym",
            estimatedMinutes: 90,
            scheduledDate: day,
            scheduledTime: makeDate(year: 2026, month: 8, day: 4, hour: 18, minute: 15),
            tags: [LifeModel.commitmentTaskTag, model.commitmentID(for: "Gym")],
            schedulingMode: .fixedTime
        )

        let synced = DayScheduleReconciler.syncCommitmentTimes(gym, model: model, day: day, calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: synced.scheduledTime!), 18)
        XCTAssertEqual(calendar.component(.minute, from: synced.scheduledTime!), 30)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
