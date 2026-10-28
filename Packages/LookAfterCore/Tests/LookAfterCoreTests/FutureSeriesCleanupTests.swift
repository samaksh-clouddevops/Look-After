import Foundation
import Testing
import LookAfterCore

struct FutureSeriesCleanupTests {
    @Test func preparingTomorrowKeepsTodaysMovedOccurrence() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: today))
        var current = LifeTask(id: "today", title: "Read", scheduledDate: today, parentTaskId: "series")
        current.userPlacedScheduleAt = Date()
        let future = LifeTask(id: "tomorrow", title: "Read", scheduledDate: tomorrow, parentTaskId: "series")
        let duplicates = TaskSeriesResolver.duplicateGroupNonKeeperIDs(
            in: [current, future], on: tomorrow, referenceDate: today
        )
        #expect(duplicates.isEmpty)
        #expect(!TaskSeriesResolver.staleActiveSeriesIDs(in: [current, future], on: tomorrow).contains(current.id))
    }

    @Test func duplicateRowsOnTomorrowAreStillDetected() throws {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: today))
        let first = LifeTask(id: "a", title: "Read", scheduledDate: tomorrow, parentTaskId: "series")
        let second = LifeTask(id: "b", title: "Read", scheduledDate: tomorrow, parentTaskId: "series")
        let duplicates = TaskSeriesResolver.duplicateGroupNonKeeperIDs(
            in: [first, second], on: tomorrow, referenceDate: today
        )
        #expect(duplicates.count == 1)
    }
}
