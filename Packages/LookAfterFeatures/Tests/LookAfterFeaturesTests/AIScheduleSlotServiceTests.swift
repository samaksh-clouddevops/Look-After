import XCTest
@testable import LookAfterFeatures
import LookAfterAI
import LookAfterCore

final class AIScheduleSlotServiceTests: XCTestCase {

    // MARK: - Golden case: calendar conflict is never overridden by any suggestion (validator-level)

    @MainActor
    func testCalendarConflictSuggestionIsRejectedNotApplied() {
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
        // AI suggests 14:00, but a calendar event occupies 13:30-14:30 that day.
        let suggestions = [
            DayScheduleSuggestion(id: "flex-1", startHour: 14, startMinute: 0, reason: "Afternoon focus", isAIGenerated: true)
        ]
        let conflictStart = Calendar.current.date(bySettingHour: 13, minute: 30, second: 0, of: day)!
        let conflictEnd = Calendar.current.date(bySettingHour: 14, minute: 30, second: 0, of: day)!
        let calendarEvent = BriefingCalendarEvent(
            id: "cal-1",
            title: "Meeting",
            startDate: conflictStart,
            timeLabel: "13:30",
            endDate: conflictEnd
        )

        let changed = AIScheduleSlotService.applySuggestions(
            suggestions,
            to: &tasks,
            on: day,
            calendarEvents: [calendarEvent]
        )

        // Behavioral/AI preference must never override a real calendar conflict.
        XCTAssertTrue(changed.isEmpty)
        XCTAssertNil(tasks[0].scheduledTime)
    }

    // MARK: - Golden case: behavior block only surfaces in the prompt when flag on + confidence gated

    @MainActor
    func testBehaviorBlockOmittedFromPromptWhenFeatureFlagDisabled() async {
        let originalFlag = TaskManagementPreferences.behaviorPersonalizedSchedulingEnabled
        TaskManagementPreferences.behaviorPersonalizedSchedulingEnabled = false
        defer { TaskManagementPreferences.behaviorPersonalizedSchedulingEnabled = originalFlag }

        var capturedPrompt: String?
        let glm = mockGLMService()
        glm.debugCompleteHandler = { prompt, _ in
            capturedPrompt = prompt
            return "[]"
        }

        let day = Calendar.current.startOfDay(for: Date())
        let task = LifeTask(
            id: "flex-1",
            title: "Deep work",
            estimatedMinutes: 45,
            schedulingMode: .flexible,
            timeConstraint: .flexible,
            userId: "u"
        )
        let snapshot = BehaviorMemorySnapshot(
            typicalDeepWorkHour: 9,
            typicalDeepWorkHourSampleCount: 20,
            typicalDeepWorkHourConfidence: .high
        )
        let context = AIScheduleSlotService.DayContext(
            day: day,
            allTasks: [task],
            unslotted: [task],
            behaviorSnapshot: snapshot
        )

        _ = await AIScheduleSlotService.suggestSlots(for: context, glm: glm)

        XCTAssertNotNil(capturedPrompt)
        XCTAssertFalse(capturedPrompt?.contains("9:00") ?? true)
    }

    @MainActor
    func testBehaviorBlockOmittedFromPromptWhenConfidenceLow() async {
        let originalFlag = TaskManagementPreferences.behaviorPersonalizedSchedulingEnabled
        TaskManagementPreferences.behaviorPersonalizedSchedulingEnabled = true
        defer { TaskManagementPreferences.behaviorPersonalizedSchedulingEnabled = originalFlag }

        var capturedPrompt: String?
        let glm = mockGLMService()
        glm.debugCompleteHandler = { prompt, _ in
            capturedPrompt = prompt
            return "[]"
        }

        let day = Calendar.current.startOfDay(for: Date())
        let task = LifeTask(
            id: "flex-1",
            title: "Deep work",
            estimatedMinutes: 45,
            schedulingMode: .flexible,
            timeConstraint: .flexible,
            userId: "u"
        )
        let snapshot = BehaviorMemorySnapshot(
            typicalDeepWorkHour: 9,
            typicalDeepWorkHourSampleCount: 20,
            typicalDeepWorkHourConfidence: .low
        )
        let context = AIScheduleSlotService.DayContext(
            day: day,
            allTasks: [task],
            unslotted: [task],
            behaviorSnapshot: snapshot
        )

        _ = await AIScheduleSlotService.suggestSlots(for: context, glm: glm)

        XCTAssertNotNil(capturedPrompt)
        XCTAssertFalse(capturedPrompt?.contains("9:00") ?? true)
    }

    @MainActor
    func testBehaviorBlockSurfacedInPromptWhenFlagEnabledAndConfidenceHigh() async {
        let originalFlag = TaskManagementPreferences.behaviorPersonalizedSchedulingEnabled
        TaskManagementPreferences.behaviorPersonalizedSchedulingEnabled = true
        defer { TaskManagementPreferences.behaviorPersonalizedSchedulingEnabled = originalFlag }

        var capturedPrompt: String?
        let glm = mockGLMService()
        glm.debugCompleteHandler = { prompt, _ in
            capturedPrompt = prompt
            return "[]"
        }

        let day = Calendar.current.startOfDay(for: Date())
        let task = LifeTask(
            id: "flex-1",
            title: "Deep work",
            estimatedMinutes: 45,
            schedulingMode: .flexible,
            timeConstraint: .flexible,
            userId: "u"
        )
        let snapshot = BehaviorMemorySnapshot(
            typicalDeepWorkHour: 9,
            typicalDeepWorkHourSampleCount: 20,
            typicalDeepWorkHourConfidence: .high
        )
        let context = AIScheduleSlotService.DayContext(
            day: day,
            allTasks: [task],
            unslotted: [task],
            behaviorSnapshot: snapshot
        )

        _ = await AIScheduleSlotService.suggestSlots(for: context, glm: glm)

        XCTAssertNotNil(capturedPrompt)
        XCTAssertTrue(capturedPrompt?.contains("9:00") ?? false)
    }

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

@MainActor
private func mockGLMService() -> GLMService {
    let glm = GLMService.makeForTesting(keyManager: GLMKeyManager(
        secretStore: InMemorySecretStore(),
        metadataKey: "ai-schedule-slot.test.\(UUID().uuidString)"
    ))
    glm.debugCompleteHandler = { _, _ in "[]" }
    glm.debugSendMessageHandler = { _, _, _, _ in "[]" }
    return glm
}
