import Foundation
import Testing
import LookAfterCore
import LookAfterAI
@testable import LookAfterFeatures

@MainActor
struct TimelineProjectionMoveTests {
    @Test func resolvingStoredOccurrencePreservesEditedClock() async throws {
        let day = Calendar.current.startOfDay(for: Date())
        let store = InMemoryTaskStore(referenceDate: day)
        let glm = GLMService()
        glm.debugCompleteHandler = { _, _ in "{}" }
        let vm = TasksViewModel(
            taskRepo: store, decomposer: TaskDecomposer(glmService: glm),
            autoFiller: TaskAutoFiller(glmService: glm), taskImporter: TaskImporter(glmService: glm),
            semanticAnalyzer: TaskSemanticAnalyzer(glmService: glm)
        )
        let original = LifeTask(
            id: "stored-occurrence", title: "Read notes", estimatedMinutes: 15,
            scheduledDate: day, scheduledTime: day.addingTimeInterval(14 * 3600),
            parentTaskId: "series", userId: "test"
        )
        try await store.create(original)
        vm.refreshFromLocal(userId: "test")
        var edited = original
        edited.id = "proj-series-today"
        edited.scheduledTime = day.addingTimeInterval(15 * 3600)
        edited.scheduledEndTime = day.addingTimeInterval(15 * 3600 + 900)
        let saved = await vm.scheduleMutation.persistTimelineEdit(edited, userId: "test")
        #expect(saved)
        let tasks = store.localAllTasks(for: "test")
        #expect(tasks.count == 1)
        let persisted = try #require(tasks.first)
        #expect(persisted.id == original.id)
        #expect(persisted.scheduledTime == edited.scheduledTime)
    }

    @Test func newProjectionGetsOneStableStoredIdentity() async throws {
        let day = Calendar.current.startOfDay(for: Date())
        let store = InMemoryTaskStore(referenceDate: day)
        let glm = GLMService()
        glm.debugCompleteHandler = { _, _ in "{}" }
        let vm = TasksViewModel(
            taskRepo: store, decomposer: TaskDecomposer(glmService: glm),
            autoFiller: TaskAutoFiller(glmService: glm), taskImporter: TaskImporter(glmService: glm)
        )
        let projection = LifeTask(
            id: "proj-new-today", title: "Read notes", scheduledDate: day,
            scheduledTime: day.addingTimeInterval(14 * 3600), parentTaskId: "series", userId: "test"
        )
        let stored = try await vm.materializeTimelineTask(projection, userId: "test")
        #expect(!stored.id.hasPrefix("proj-"))
        let resolvedAgain = try await vm.materializeTimelineTask(projection, userId: "test")
        #expect(stored.id == resolvedAgain.id)
        #expect(store.localAllTasks(for: "test").count == 1)
    }
}
