import XCTest
@testable import LookAfterFeatures
@testable import LookAfterAI
import LookAfterCore
import LookAfterData

final class DailyBriefingViewModelTests: XCTestCase {

    @MainActor
    func testVisibleCardsRespectsHiddenAndPinned() {
        let vm = DailyBriefingViewModel()
        vm.resetCardLayout()
        vm.setCardHidden(.habits, hidden: true)
        vm.togglePin(.dailySummary)

        XCTAssertFalse(vm.visibleCards.contains(.habits))
        XCTAssertEqual(vm.visibleCards.first, .dailySummary)
    }

    @MainActor
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
        let today = Calendar.current.startOfDay(for: Date())
        tasksVM.tasks = [
            LifeTask(title: "Vision API Review", priority: .high, scheduledDate: today),
            LifeTask(title: "Gym", priority: .medium, scheduledDate: today),
        ]
        tasksVM.completedToday = [
            LifeTask(
                title: "Morning standup",
                status: .completed,
                scheduledDate: today,
                completedAt: Date()
            ),
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

    @MainActor
    func testRefreshBuildsLiveHealthSnapshotWithoutOvernightSleep() async {
        let vm = DailyBriefingViewModel()
        let brain = ExecutiveBrain(glmService: mockGLMService())
        let brainVM = BrainViewModel(brain: brain)
        let tasksVM = TasksViewModel(decomposer: TaskDecomposer(glmService: mockGLMService()))

        brainVM.cognitiveSnapshot = CognitiveSnapshot(
            energy: .high,
            energyScore: 0.78,
            recoveryScore: 0.62,
            executiveFunctionScore: 74
        )

        await vm.refresh(
            brainVM: brainVM,
            tasksVM: tasksVM,
            userId: "user-1",
            userName: "Alex",
            healthKitAvailable: false
        )

        XCTAssertFalse(vm.healthSnapshot.hasOvernightHealthSignal)
        XCTAssertEqual(vm.healthSnapshot.energyPercent, 78)
        XCTAssertEqual(vm.healthSnapshot.recoveryPercent, 62)
        XCTAssertEqual(vm.healthSnapshot.readinessScore, 74)
    }

    @MainActor
    func testRefreshTaskProgressRebuildsHealthSnapshot() async {
        let vm = DailyBriefingViewModel()
        let brain = ExecutiveBrain(glmService: mockGLMService())
        let brainVM = BrainViewModel(brain: brain)
        let tasksVM = TasksViewModel(decomposer: TaskDecomposer(glmService: mockGLMService()))

        brainVM.cognitiveSnapshot = CognitiveSnapshot(
            energyScore: 0.55,
            recoveryScore: 0.48,
            executiveFunctionScore: 58
        )

        await vm.refresh(
            brainVM: brainVM,
            tasksVM: tasksVM,
            userId: "user-1",
            userName: "Alex",
            healthKitAvailable: false
        )
        XCTAssertEqual(vm.healthSnapshot.readinessScore, 58)

        brainVM.cognitiveSnapshot = CognitiveSnapshot(
            energyScore: 0.82,
            recoveryScore: 0.71,
            executiveFunctionScore: 85
        )
        vm.refreshTaskProgress(
            brainVM: brainVM,
            tasksVM: tasksVM,
            healthKitAvailable: false
        )

        XCTAssertEqual(vm.healthSnapshot.readinessScore, 85)
        XCTAssertEqual(vm.healthSnapshot.energyPercent, 82)
        XCTAssertEqual(vm.healthSnapshot.recoveryPercent, 71)
    }

    @MainActor
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

    @MainActor
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

    @MainActor
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

@MainActor
private func mockGLMService(stub: String = "") -> GLMService {
    let glm = GLMService.makeForTesting(keyManager: GLMKeyManager(
        secretStore: InMemorySecretStore(),
        metadataKey: "briefing.test.\(UUID().uuidString)"
    ))
    glm.debugCompleteHandler = { _, _ in stub }
    glm.debugSendMessageHandler = { _, _, _, _ in stub }
    return glm
}
