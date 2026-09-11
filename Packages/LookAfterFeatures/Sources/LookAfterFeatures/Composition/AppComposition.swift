import Foundation
import LookAfterCore
import LookAfterAI
import LookAfterData

/// Composition root for feature-layer dependencies (Q3 architecture).
/// Prefer constructing through here instead of ad-hoc `.shared` soup at call sites.
@MainActor
public struct AppComposition {
    public let glm: GLMService
    public let taskStore: TaskStore
    public let timelineService: TimelineService
    public let healthStore: HealthStore

    public init(
        glm: GLMService = .shared,
        taskStore: TaskStore = .shared,
        timelineService: TimelineService = .shared,
        healthStore: HealthStore = .shared
    ) {
        self.glm = glm
        self.taskStore = taskStore
        self.timelineService = timelineService
        self.healthStore = healthStore
    }

    public static let live = AppComposition()

    public func makeTasksViewModel(
        decomposer: TaskDecomposer? = nil,
        autoFiller: TaskAutoFiller? = nil
    ) -> TasksViewModel {
        TasksViewModel(
            taskStore: taskStore,
            decomposer: decomposer ?? TaskDecomposer(glmService: glm),
            autoFiller: autoFiller
        )
    }

    public func makeInboxViewModel(inboxRepo: InboxRepository? = nil) -> InboxViewModel {
        InboxViewModel(inboxRepo: inboxRepo, glmService: glm)
    }

    public func makeBriefingViewModel() -> DailyBriefingViewModel {
        DailyBriefingViewModel()
    }

    public func makeADHDViewModel() -> ADHDViewModel {
        ADHDViewModel()
    }

    public func makeModulesViewModel() -> LifeModulesViewModel {
        LifeModulesViewModel()
    }

    public func makeContextOrchestrator() -> ContextOrchestrator {
        ContextOrchestrator(glmService: glm)
    }
}
