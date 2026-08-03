import XCTest
@testable import LifeOSCore
@testable import LifeOSFeatures

final class DayAssemblerTests: XCTestCase {

    func testCreatesGymAndMusicTasksForWeekday() {
        let markdown = """
        ### Gym
        **6:30 PM – 8:00 PM**
        ### Dinner & Recovery
        **8:00 PM – 9:00 PM**
        ### Creative Deep Work
        **9:00 PM – 11:30 PM**
        Priority order:
        1. Music production
        2. Songwriting
        """
        let model = LifeModelValidator.compileLocally(from: markdown)
        let weekday = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 4))!

        let result = DayAssembler.assemble(
            model: model,
            existingTasks: [],
            completedToday: [],
            userId: "test-user",
            date: weekday
        )

        XCTAssertTrue(result.tasksToCreate.contains { $0.title == "Gym" })
        XCTAssertTrue(result.tasksToCreate.contains { $0.title == "Dinner" })
        XCTAssertTrue(result.tasksToCreate.contains { $0.title == "Music production" })
        XCTAssertFalse(result.tasksToCreate.contains { $0.title == "Songwriting" })

        let gym = result.tasksToCreate.first { $0.title == "Gym" }
        XCTAssertEqual(gym?.scheduledTime.flatMap { Calendar.current.component(.hour, from: $0) }, 18)
        XCTAssertEqual(gym?.scheduledTime.flatMap { Calendar.current.component(.minute, from: $0) }, 30)

        let dinner = result.tasksToCreate.first { $0.title == "Dinner" }
        XCTAssertNotNil(dinner)
        XCTAssertEqual(dinner?.scheduledTime.flatMap { Calendar.current.component(.hour, from: $0) }, 20)

        let music = result.tasksToCreate.first { $0.title == "Music production" }
        XCTAssertNotNil(music)
        XCTAssertEqual(music?.scheduledTime.flatMap { Calendar.current.component(.hour, from: $0) }, 21)
        XCTAssertEqual(music?.schedulingModeValue, .fixedTime)
        XCTAssertEqual(music?.recurrenceRule, TaskRecurrence.none)
        XCTAssertTrue(music?.tags.contains(LifeModel.commitmentTaskTag) == true)
    }

    func testSkipsCreativeCommitmentWhenMultiDaySliceExists() {
        let markdown = """
        ### Creative Deep Work
        **9:00 PM – 11:30 PM**
        Priority order:
        1. Music production
        """
        let model = LifeModelValidator.compileLocally(from: markdown)
        let weekday = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 4))!

        let existingSlice = LifeTask(
            title: "Day 1: Album mix",
            lifeArea: .creativity,
            estimatedMinutes: 60,
            scheduledDate: weekday,
            tags: [MultiDayTaskTags.slice],
            userId: "test-user"
        )

        let result = DayAssembler.assemble(
            model: model,
            existingTasks: [existingSlice],
            completedToday: [],
            userId: "test-user",
            date: weekday
        )

        XCTAssertFalse(result.tasksToCreate.contains { $0.title == "Music production" })
        XCTAssertTrue(result.skippedTitles.contains("Music production"))
    }
}
