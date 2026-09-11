import XCTest
@testable import LookAfterFeatures
@testable import LookAfterAI
import LookAfterCore
import LookAfterData

final class ExecutivePlanningVoiceTests: XCTestCase {
    @MainActor
    func testOnSpeakReplyOnlyWhenVoiceMode() async {
        let glm = failingGLMService()
        let engine = LLMPlanningEngine(glmService: glm)
        let planningVM = ExecutivePlanningViewModel(engine: engine)
        let tasksVM = TasksViewModel(decomposer: TaskDecomposer(glmService: glm))
        let modulesVM = LifeModulesViewModel()

        var speakCount = 0
        planningVM.onSpeakReply = { _ in speakCount += 1 }

        let context = PlanningConversationContext(
            userName: "Test",
            tasks: [],
            timelineItems: [],
            medications: [],
            availableMinutes: 120,
            energyPercent: 55
        )

        await planningVM.submit(
            text: "add email task",
            startedWithVoice: false,
            context: context,
            tasksVM: tasksVM,
            modulesVM: modulesVM,
            userId: "user-1",
            refreshContext: {}
        )
        XCTAssertEqual(speakCount, 0)
        XCTAssertEqual(planningVM.inputMode, .text)

        planningVM.factoryReset()
        speakCount = 0

        await planningVM.submit(
            text: "add email task",
            startedWithVoice: true,
            context: context,
            tasksVM: tasksVM,
            modulesVM: modulesVM,
            userId: "user-1",
            refreshContext: {}
        )
        XCTAssertEqual(speakCount, 1)
        XCTAssertEqual(planningVM.inputMode, .voice)
    }

    @MainActor
    func testSeedProactiveSuggestionsOnlyRunsOnce() {
        let planningVM = ExecutivePlanningViewModel()
        planningVM.seedProactiveSuggestionsIfNeeded(tasks: [])
        let turnCount = planningVM.turns.count
        planningVM.seedProactiveSuggestionsIfNeeded(tasks: [])
        XCTAssertEqual(planningVM.turns.count, turnCount)
    }
}

@MainActor
private func failingGLMService() -> GLMService {
    let glm = GLMService.makeForTesting(keyManager: GLMKeyManager(
        secretStore: InMemorySecretStore(),
        metadataKey: "voice.test.\(UUID().uuidString)"
    ))
    glm.debugSendMessageHandler = { _, _, _, _ in
        throw NSError(domain: "ExecutivePlanningVoiceTests", code: 1)
    }
    return glm
}
