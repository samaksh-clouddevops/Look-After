import Foundation
import LookAfterCore

/// Persistence contract for task lists — implemented by `TaskRepository` and `TaskStore`.
@MainActor
public protocol TaskStoring {
    func localSnapshot(for userId: String) -> TaskListSnapshot
    func localAllTasks(for userId: String) -> [LifeTask]
    func getTaskLists(for userId: String) async throws -> TaskListSnapshot
    func getActive(for userId: String) async throws -> [LifeTask]
    func getCompletedToday(for userId: String) async throws -> [LifeTask]
    func getAll(for userId: String) async throws -> [LifeTask]
    func create(_ task: LifeTask) async throws
    func update(_ task: LifeTask) async throws
    func delete(_ id: String) async throws
}

extension TaskRepository: TaskStoring {}
