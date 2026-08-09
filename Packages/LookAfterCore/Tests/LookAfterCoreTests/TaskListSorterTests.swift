import XCTest
@testable import LookAfterCore

final class TaskListSorterTests: XCTestCase {
    private let calendar = TestCalendarFixtures.calendar
    private var today: Date { TestCalendarFixtures.today }

    func testEqualScheduledTimeSortIsStableByTaskID() {
        let sharedTime = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today)!
        let tasks = [
            LifeTask(id: "b-task", title: "Beta", scheduledDate: today, scheduledTime: sharedTime, userId: "user-1"),
            LifeTask(id: "a-task", title: "Alpha", scheduledDate: today, scheduledTime: sharedTime, userId: "user-1"),
            LifeTask(id: "c-task", title: "Charlie", scheduledDate: today, scheduledTime: sharedTime, userId: "user-1"),
        ]

        let first = TaskListSorter.sortForToday(tasks, calendar: calendar, now: today)
        let second = TaskListSorter.sortForToday(tasks.shuffled(), calendar: calendar, now: today)

        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first.map(\.id), ["a-task", "b-task", "c-task"])
    }

    func testEqualPriorityAndScheduleSortIsStableByTaskID() {
        let sharedTime = calendar.date(bySettingHour: 14, minute: 30, second: 0, of: today)!
        let tasks = [
            LifeTask(id: "z", title: "Z", priority: .high, scheduledDate: today, scheduledTime: sharedTime, userId: "user-1"),
            LifeTask(id: "a", title: "A", priority: .high, scheduledDate: today, scheduledTime: sharedTime, userId: "user-1"),
            LifeTask(id: "m", title: "M", priority: .high, scheduledDate: today, scheduledTime: sharedTime, userId: "user-1"),
        ]

        let sorted = TaskListSorter.sortByPriorityThenSchedule(tasks.shuffled())
        XCTAssertEqual(sorted.map(\.id), ["a", "m", "z"])
    }
}
