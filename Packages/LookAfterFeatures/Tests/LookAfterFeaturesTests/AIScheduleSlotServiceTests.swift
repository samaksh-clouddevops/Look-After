import XCTest
@testable import LookAfterFeatures
import LookAfterCore

final class AIScheduleSlotServiceTests: XCTestCase {

    @MainActor
    func testApplySuggestionsSetsScheduledTimeWithoutAnchoring() {
        let day = Calendar.current.startOfDay(for: Date())
        var tasks = [
            LifeTask(
                id: "flex-1",
                title: "Deep work",
                estimatedMinutes: 45,
                schedulingMode: .flexible,
                timeConstraint: .flexible,
                userId: "u"
            )
        ]
        let suggestions = [
            DayScheduleSuggestion(id: "flex-1", startHour: 14, startMinute: 0, reason: "Afternoon focus")
        ]

        let changed = AIScheduleSlotService.applySuggestions(suggestions, to: &tasks, on: day)

        XCTAssertEqual(changed, ["flex-1"])
        XCTAssertEqual(tasks[0].timeConstraintValue, .flexible)
        XCTAssertNotNil(tasks[0].scheduledTime)
        XCTAssertNotNil(tasks[0].scheduledEndTime)
        let hour = Calendar.current.component(.hour, from: tasks[0].scheduledTime!)
        XCTAssertEqual(hour, 14)
    }

    @MainActor
    func testApplySuggestionsSkipsAnchoredTasks() {
        let day = Calendar.current.startOfDay(for: Date())
        var tasks = [
            LifeTask(
                id: "anchored-1",
                title: "Meeting",
                schedulingMode: .fixedTime,
                timeConstraint: .anchored,
                userId: "u"
            )
        ]
        let suggestions = [
            DayScheduleSuggestion(id: "anchored-1", startHour: 11, startMinute: 0)
        ]

        let changed = AIScheduleSlotService.applySuggestions(suggestions, to: &tasks, on: day)

        XCTAssertTrue(changed.isEmpty)
        XCTAssertNil(tasks[0].scheduledTime)
    }
}
