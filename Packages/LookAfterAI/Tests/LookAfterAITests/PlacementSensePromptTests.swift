import XCTest
import LookAfterCore
@testable import LookAfterAI

final class PlacementSensePromptTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func day() -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
    }

    private func time(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day())!
    }

    // MARK: - Prompt rendering: omits optional blocks when nil/empty

    func testPromptOmitsOptionalBlocksWhenNoDataProvided() {
        let task = LifeTask(title: "Gym", estimatedMinutes: 60, scheduledDate: day())
        let prompt = LookAfterPrompts.placementSensePrompt(
            task: task,
            proposedStart: time(15),
            durationMinutes: 60,
            neighborTasks: [],
            calendar: calendar
        )
        XCTAssertFalse(prompt.contains("CALENDAR EVENTS TODAY"))
        XCTAssertFalse(prompt.contains("USER STATE"))
        XCTAssertFalse(prompt.contains("WEATHER:"))
        XCTAssertFalse(prompt.contains("Deadline:"))
        XCTAssertFalse(prompt.contains("previously accepted at this same time"))
        // Core blocks always present.
        XCTAssertTrue(prompt.contains("NOW:"))
        XCTAssertTrue(prompt.contains("HOW TODAY LOOKS"))
        XCTAssertTrue(prompt.contains("\"confidence\""))
        XCTAssertTrue(prompt.contains("AI/allocator guessed this slot"))
    }

    // MARK: - Prompt rendering: includes blocks when data is present

    func testPromptIncludesCalendarDeadlineHealthWeatherWhenProvided() {
        var task = LifeTask(title: "Pack bag", estimatedMinutes: 40, scheduledDate: day())
        task.deadline = time(20)
        task.userPlacedScheduleAt = time(15)

        let event = BriefingCalendarEvent(
            id: "e1",
            title: "Dentist",
            startDate: time(16),
            timeLabel: "16:00",
            endDate: time(17)
        )
        let health = HealthSummary(id: "h1", date: day(), totalSleepMinutes: 420, hrvAverage: 55)
        let energy = EnergyReport(energy: .moderate)

        let prompt = LookAfterPrompts.placementSensePrompt(
            task: task,
            proposedStart: time(15),
            durationMinutes: 40,
            neighborTasks: [],
            calendar: calendar,
            calendarEvents: [event],
            todayHealthSummary: health,
            todayEnergy: energy,
            weatherSummary: "Rainy, 12C",
            previousAcceptedSameSlot: true
        )

        XCTAssertTrue(prompt.contains("CALENDAR EVENTS TODAY"))
        XCTAssertTrue(prompt.contains("Dentist"))
        XCTAssertTrue(prompt.contains("Deadline:"))
        XCTAssertTrue(prompt.contains("USER STATE"))
        XCTAssertTrue(prompt.contains("WEATHER: Rainy, 12C"))
        XCTAssertTrue(prompt.contains("previously accepted at this same time"))
        XCTAssertTrue(prompt.contains("USER manually placed this"))
    }

    func testPromptContainsNegativeConstraintGuardrails() {
        let task = LifeTask(title: "Review notes", estimatedMinutes: 30, scheduledDate: day())
        let prompt = LookAfterPrompts.placementSensePrompt(
            task: task,
            proposedStart: time(13),
            durationMinutes: 30,
            neighborTasks: [],
            calendar: calendar
        )
        XCTAssertTrue(prompt.contains("Do not reject a slot merely because it seems unusual"))
        XCTAssertTrue(prompt.contains("A free/empty slot alone does not make a placement valid"))
        XCTAssertTrue(prompt.contains("Never invent times, task ids, or titles"))
        XCTAssertTrue(prompt.contains("prefer \"allowed\": false"))
    }

    // MARK: - judgePlacement: confidence parsing

    @MainActor
    func testJudgePlacementParsesConfidenceField() async throws {
        let glm = MockGLM.service(stubbedResponse: """
        {"allowed": true, "reason": "fine", "confidence": 0.42}
        """)
        let analyzer = TaskSemanticAnalyzer(glmService: glm)
        let task = LifeTask(title: "Gym", estimatedMinutes: 60, scheduledDate: day())

        let judgment = try await analyzer.judgePlacement(
            task: task,
            proposedStart: time(15),
            durationMinutes: 60,
            neighborTasks: [],
            calendar: calendar
        )

        XCTAssertTrue(judgment.allowed)
        XCTAssertEqual(judgment.confidence, 0.42, accuracy: 0.0001)
    }

    @MainActor
    func testJudgePlacementDefaultsConfidenceWhenLegacyResponseOmitsField() async throws {
        let glm = MockGLM.service(stubbedResponse: """
        {"allowed": false, "reason": "too late", "suggestedStartHour": 9, "suggestedStartMinute": 0}
        """)
        let analyzer = TaskSemanticAnalyzer(glmService: glm)
        let task = LifeTask(title: "Errand", estimatedMinutes: 30, scheduledDate: day())

        let judgment = try await analyzer.judgePlacement(
            task: task,
            proposedStart: time(22),
            durationMinutes: 30,
            neighborTasks: [],
            calendar: calendar
        )

        XCTAssertFalse(judgment.allowed)
        XCTAssertEqual(judgment.suggestedStartHour, 9)
        // Back-compat default for legacy-shaped responses.
        XCTAssertEqual(judgment.confidence, 1.0, accuracy: 0.0001)
    }
}
