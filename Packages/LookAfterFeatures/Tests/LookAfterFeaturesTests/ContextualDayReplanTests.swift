import XCTest
@testable import LookAfterFeatures
@testable import LookAfterAI
import LookAfterCore
import LookAfterData

@MainActor
final class ContextualDayReplanTests: XCTestCase {
    private let calendar = TestCalendarFixtures.calendar
    private var today: Date { TestCalendarFixtures.today }

    func testPostWakeLocalFallbackDefersMissedFlexibleTasks() async {
        let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
        let now = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: today)!
        let missed = LifeTask(
            title: "Morning block",
            estimatedMinutes: 30,
            scheduledDate: today,
            scheduledTime: nine,
            schedulingMode: .flexible,
            userId: "user-1"
        )
        let upcoming = LifeTask(
            title: "Afternoon task",
            estimatedMinutes: 30,
            scheduledDate: today,
            scheduledTime: calendar.date(bySettingHour: 15, minute: 0, second: 0, of: today)!,
            schedulingMode: .flexible,
            userId: "user-1"
        )

        let glm = offlineGLM()
        let engine = DayReplanEngine(glmService: glm)
        let context = makeContext(
            tasks: [missed, upcoming],
            trigger: .postWake,
            missedTasks: [missed],
            wakeTime: now,
            minutesLate: 120
        )

        let result = try? await engine.replan(context: context)
        XCTAssertNotNil(result)
        let deferred = result?.scheduleChanges.first { $0.taskID == missed.id }
        XCTAssertTrue(deferred?.deferToTomorrow == true)
    }

    func testFreedSlotLocalFallbackFillsOpenWindow() async {
        let slotStart = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: today)!
        let slotEnd = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: today)!
        let candidate = LifeTask(
            title: "Email inbox",
            priority: .high,
            estimatedMinutes: 30,
            scheduledDate: today,
            schedulingMode: .flexible,
            userId: "user-1"
        )
        let tooLong = LifeTask(
            title: "Deep work",
            estimatedMinutes: 90,
            scheduledDate: today,
            schedulingMode: .flexible,
            userId: "user-1"
        )

        let glm = offlineGLM()
        let engine = DayReplanEngine(glmService: glm)
        let context = makeContext(
            tasks: [candidate, tooLong],
            trigger: .freedSlot,
            freedSlotWindow: DayReplanAwayWindow(start: slotStart, end: slotEnd),
            removedTaskTitle: "Vocal Practice"
        )

        let result = try? await engine.replan(context: context)
        XCTAssertNotNil(result)
        let change = result?.scheduleChanges.first { $0.taskID == candidate.id }
        XCTAssertNotNil(change)
        XCTAssertFalse(change?.deferToTomorrow ?? true)
        XCTAssertNil(result?.scheduleChanges.first { $0.taskID == tooLong.id })
    }

    func testGoingOutLocalFallbackAvoidsAwayWindow() async {
        let departure = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: today)!
        let end = calendar.date(bySettingHour: 16, minute: 0, second: 0, of: today)!
        let task = LifeTask(
            title: "Write",
            estimatedMinutes: 30,
            scheduledDate: today,
            scheduledTime: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today)!,
            schedulingMode: .flexible,
            userId: "user-1"
        )

        let glm = offlineGLM()
        let engine = DayReplanEngine(glmService: glm)
        let constraint = UserDayConstraint.goingOut(departure: departure, durationMinutes: 120, calendar: calendar)
        let context = makeContext(
            tasks: [task],
            trigger: .goingOut,
            constraint: constraint,
            awayWindow: DayReplanAwayWindow(start: departure, end: end)
        )

        let result = try? await engine.replan(context: context)
        XCTAssertNotNil(result)
        let change = result?.scheduleChanges.first { $0.taskID == task.id }
        XCTAssertNotNil(change)
        if let hour = change?.startHour {
            XCTAssertTrue(hour < 14 || change?.deferToTomorrow == true)
        }
    }

    private func makeContext(
        tasks: [LifeTask],
        trigger: DayReplanTrigger,
        missedTasks: [LifeTask] = [],
        wakeTime: Date? = nil,
        minutesLate: Int? = nil,
        constraint: UserDayConstraint? = nil,
        awayWindow: DayReplanAwayWindow? = nil,
        freedSlotWindow: DayReplanAwayWindow? = nil,
        removedTaskTitle: String? = nil
    ) -> DayReplanContext {
        let planning = PlanningConversationContext(
            userName: "Test",
            tasks: tasks,
            timelineItems: [],
            medications: [],
            availableMinutes: 240,
            energyPercent: 70,
            executiveCapacityLabel: "Steady",
            executiveCapacityReasons: [],
            planSummary: "",
            completedTodayCount: 0,
            lifeProfile: UserLifeProfile(),
            analyticsContext: nil,
            healthSummary: nil
        )
        var active = constraint
        if active == nil, trigger == .postWake, let wakeTime {
            active = UserDayConstraint.postWake(wakeTime: wakeTime, calendar: calendar)
        }
        return DayReplanContext(
            planningContext: planning,
            completedTasks: [],
            trigger: trigger,
            activeConstraint: active,
            missedTasks: missedTasks,
            awayWindow: awayWindow,
            minutesLate: minutesLate,
            freedSlotWindow: freedSlotWindow,
            removedTaskTitle: removedTaskTitle
        )
    }

    private func offlineGLM() -> GLMService {
        let glm = GLMService.makeForTesting(keyManager: GLMKeyManager(
            secretStore: InMemorySecretStore(),
            metadataKey: "contextual.replan.\(UUID().uuidString)"
        ))
        glm.debugSendMessageHandler = { _, _, _, _ in
            throw GLMServiceError.noKeysConfigured
        }
        return glm
    }
}
