import XCTest
@testable import LookAfterCore

final class MultiDayVisibilityTests: XCTestCase {
    func testMultiDaySliceMatchesScheduleAndIsNotInvalid() {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        let root = LifeTask(
            id: "root-1",
            title: "Ship feature",
            status: .pending,
            tags: [MultiDayTaskTags.root],
            userId: "u1"
        )
        let slice = LifeTask(
            id: "slice-1",
            title: "Ship feature · Day 1",
            status: .pending,
            scheduledDate: day,
            scheduledTime: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day),
            tags: [MultiDayTaskTags.slice],
            parentTaskId: root.id,
            userId: "u1"
        )

        XCTAssertTrue(
            TaskRecurrenceEngine.matchesRecurrenceSchedule(slice, on: day, in: [root, slice], calendar: calendar)
        )
        XCTAssertTrue(
            TaskRecurrenceEngine.invalidScheduledTaskIDs(in: [root, slice], calendar: calendar).isEmpty
        )
        XCTAssertEqual(TaskScheduleQuery.seriesKey(for: slice), "multiday-slice|slice-1")
        XCTAssertNotEqual(TaskScheduleQuery.seriesKey(for: slice), TaskScheduleQuery.seriesKey(for: root))
    }

    func testUniqueActiveTasksKeepsEveryMultiDaySlice() {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        let root = LifeTask(
            id: "root-1",
            title: "Ship feature",
            status: .pending,
            tags: [MultiDayTaskTags.root],
            userId: "u1"
        )
        let slice1 = LifeTask(
            id: "slice-1",
            title: "Ship feature · Day 1",
            status: .pending,
            scheduledDate: day,
            tags: [MultiDayTaskTags.slice],
            parentTaskId: root.id,
            userId: "u1"
        )
        let day2 = calendar.date(byAdding: .day, value: 1, to: day)!
        let slice2 = LifeTask(
            id: "slice-2",
            title: "Ship feature · Day 2",
            status: .pending,
            scheduledDate: day2,
            tags: [MultiDayTaskTags.slice],
            parentTaskId: root.id,
            userId: "u1"
        )

        let unique = TaskScheduleQuery.uniqueActiveTasks(
            from: [root, slice1, slice2],
            context: [root, slice1, slice2],
            calendar: calendar,
            referenceDate: day
        )
        XCTAssertEqual(Set(unique.map(\.id)), Set(["root-1", "slice-1", "slice-2"]))
    }
}
