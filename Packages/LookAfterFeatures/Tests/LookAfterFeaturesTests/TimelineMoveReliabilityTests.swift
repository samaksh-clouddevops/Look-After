import Foundation
import Testing
import LookAfterCore
@testable import LookAfterFeatures

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TimelineMoveReliabilityTests {
    private func task() -> LifeTask {
        let day = Calendar.current.startOfDay(for: Date())
        return LifeTask(
            id: "move-test", title: "Read notes", estimatedMinutes: 15,
            scheduledDate: day, scheduledTime: day.addingTimeInterval(14 * 3600),
            schedulingMode: .flexible, timeConstraint: .flexible, userId: "test"
        )
    }

    @Test func failedConstraintSaveRestoresOriginalState() async {
        let vm = TimelineConstraintViewModel()
        vm.seed(tasks: [task()])
        vm.persistTask = { _ in false }
        vm.handle(.setConstraint(taskID: "move-test", .anchored))
        #expect(vm.savingTaskIDs.contains("move-test"))
        while !vm.savingTaskIDs.isEmpty { await Task.yield() }
        #expect(vm.constraint(for: "move-test") == .flexible)
        #expect(vm.mutationError != nil)
    }

    @Test func pendingSaveBlocksDuplicateMutation() async {
        let vm = TimelineConstraintViewModel()
        vm.seed(tasks: [task()])
        var writes = 0
        vm.persistTask = { _ in writes += 1; return true }
        vm.handle(.setConstraint(taskID: "move-test", .anchored))
        vm.handle(.setConstraint(taskID: "move-test", .fluid))
        while !vm.savingTaskIDs.isEmpty { await Task.yield() }
        #expect(writes == 1)
        #expect(vm.constraint(for: "move-test") == .anchored)
    }

    @Test func failedMoveDoesNotReportSuccess() async {
        let vm = TimelineConstraintViewModel()
        vm.lifeModelProvider = { nil }
        let original = task()
        vm.seed(tasks: [original])
        var commits = 0
        var writes = 0
        vm.persistTask = { _ in writes += 1; return false }
        vm.onScheduleDragCommitted = { commits += 1 }
        vm.handle(.commitVerticalOffset(taskID: original.id, offsetMinutes: 15))
        while !vm.savingTaskIDs.isEmpty { await Task.yield() }
        #expect(writes == 1)
        #expect(commits == 0)
        #expect(vm.savedStart == nil)
        #expect(vm.mutationError != nil)
    }

    @Test func successfulMoveReportsPersistedTime() async throws {
        let vm = TimelineConstraintViewModel()
        vm.lifeModelProvider = { nil }
        let original = task()
        vm.seed(tasks: [original])
        var savedTask: LifeTask?
        var commits = 0
        vm.persistTask = { savedTask = $0; return true }
        vm.onScheduleDragCommitted = { commits += 1 }
        vm.handle(.commitVerticalOffset(taskID: original.id, offsetMinutes: 15))
        #expect(commits == 0)
        while !vm.savingTaskIDs.isEmpty { await Task.yield() }
        let saved = try #require(savedTask)
        #expect(commits == 1)
        #expect(saved.scheduledTime == original.scheduledTime?.addingTimeInterval(900))
        #expect(vm.savedStart == saved.scheduledTime)
    }
}
