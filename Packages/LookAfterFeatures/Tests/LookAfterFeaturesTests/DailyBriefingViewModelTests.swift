import XCTest
@testable import LookAfterFeatures
@testable import LookAfterAI
import LookAfterCore
import LookAfterData

@MainActor
final class DailyBriefingViewModelTests: XCTestCase {

    func testVisibleCardsRespectsHiddenAndPinned() {
        let vm = DailyBriefingViewModel()
        vm.resetCardLayout()
        vm.setCardHidden(.habits, hidden: true)
        vm.togglePin(.dailySummary)

        XCTAssertFalse(vm.visibleCards.contains(.habits))
        XCTAssertEqual(vm.visibleCards.first, .dailySummary)
    }

    func testRefreshBuildsGreetingAndMission() async {
        let vm = DailyBriefingViewModel()
        let glm = mockGLMService()
        let brain = ExecutiveBrain(glmService: glm)
        let brainVM = BrainViewModel(brain: brain)
        let decomposer = TaskDecomposer(glmService: glm)
        let tasksVM = TasksViewModel(decomposer: decomposer)

        brainVM.cognitiveSnapshot = CognitiveSnapshot(
            contextNotes: "Strong day for deep work.",
            executiveFunctionScore: 82
        )
        brainVM.topTasks = [
            LifeTask(title: "Vision API Review", priority: .high),
            LifeTask(title: "Gym", priority: .medium),
        ]
        tasksVM.completedToday = [
            LifeTask(title: "Morning standup", status: .completed),
        ]

        await vm.refresh(
            brainVM: brainVM,
            tasksVM: tasksVM,
            userId: "user-1",
            userName: "Alex",
            healthKitAvailable: false
        )

        XCTAssertEqual(vm.dailySummary.score, 82)
        XCTAssertFalse(vm.greeting.timeGreeting.isEmpty)
        XCTAssertFalse(vm.mission.tasks.isEmpty)
        XCTAssertEqual(vm.progress.completedCount, 1)
    }

    func testGreetingDoesNotDuplicateUserNameWhenHeroBriefingIncludesName() async {
        let vm = DailyBriefingViewModel()
        let brain = ExecutiveBrain(glmService: mockGLMService())
        let brainVM = BrainViewModel(brain: brain)
        let tasksVM = TasksViewModel(decomposer: TaskDecomposer(glmService: mockGLMService()))

        await vm.refresh(
            brainVM: brainVM,
            tasksVM: tasksVM,
            userId: "user-1",
            userName: "Alex",
            healthKitAvailable: false,
            heroBriefing: HeroBriefing(
                greeting: "Good evening, Alex",
                actionLine: "Review Azure deployment",
                supportingLine: "A focused push now makes the rest of today lighter.",
                buttonLabel: "Start now",
                action: ContextAction(label: "Start now", kind: .beginWork)
            )
        )

        XCTAssertEqual(vm.greeting.timeGreeting, "Good evening, Alex")
        XCTAssertTrue(vm.greeting.userName.isEmpty)
    }

    func testGreetingDoesNotDuplicateUserNameWhenFlowGreetingIncludesName() async {
        let vm = DailyBriefingViewModel()
        let brain = ExecutiveBrain(glmService: mockGLMService())
        let brainVM = BrainViewModel(brain: brain)
        let tasksVM = TasksViewModel(decomposer: TaskDecomposer(glmService: mockGLMService()))

        brainVM.setFlowSurfaceForTesting(FlowSurface(greeting: "Good afternoon, Alex."))

        await vm.refresh(
            brainVM: brainVM,
            tasksVM: tasksVM,
            userId: "user-1",
            userName: "Alex",
            healthKitAvailable: false
        )

        XCTAssertEqual(vm.greeting.timeGreeting, "Good afternoon, Alex")
        XCTAssertTrue(vm.greeting.userName.isEmpty, "userName should be empty to prevent duplication in UI view")
    }

    func testToggleHabitPersistsForToday() {
        UserDefaults.standard.removeObject(forKey: "briefingHabitCompletions")
        let vm = DailyBriefingViewModel()
        let habitID = "water"

        guard let habit = vm.habits.first(where: { $0.id == habitID }) else {
            XCTFail("Expected water habit")
            return
        }

        XCTAssertFalse(habit.isCompletedToday)

        vm.toggleHabit(habit)
        XCTAssertTrue(vm.habits.first(where: { $0.id == habitID })?.isCompletedToday == true)

        vm.toggleHabit(habit)
        XCTAssertFalse(vm.habits.first(where: { $0.id == habitID })?.isCompletedToday == true)
    }
}

private func mockGLMService(stub: String = "") -> GLMService {
    let glm = GLMService.makeForTesting(keyManager: GLMKeyManager(
        secretStore: InMemorySecretStore(),
        metadataKey: "briefing.test.\(UUID().uuidString)"
    ))
    glm.debugCompleteHandler = { _ in stub }
    glm.debugSendMessageHandler = { _, _, _ in stub }
    return glm
}
