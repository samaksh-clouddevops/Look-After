import Foundation
import LookAfterCore

/// Persistence contract for task lists — implemented by `TaskRepository` and `TaskStore`.
@MainActor
public protocol TaskStoring {
    /// Off-main disk hydrate of the local task list. Call before first snapshot on cold launch.
    func warmLocalCache(for userId: String) async
    func localSnapshot(for userId: String) -> TaskListSnapshot
    func localAllTasks(for userId: String) -> [LifeTask]
    func getTaskLists(for userId: String) async throws -> TaskListSnapshot
    func getActive(for userId: String) async throws -> [LifeTask]
    func getCompletedToday(for userId: String) async throws -> [LifeTask]
    func getAll(for userId: String) async throws -> [LifeTask]
    func create(_ task: LifeTask) async throws
    func update(_ task: LifeTask) async throws
    func updateMany(_ tasks: [LifeTask]) async throws
    func delete(_ id: String) async throws
    @discardableResult
    func pruneTerminalRecurrenceOccurrences(for userId: String, retentionDays: Int) -> Int
    @discardableResult
    func compactRecurrenceStorage(for userId: String, retentionDays: Int) -> Int
    @discardableResult
    func compactRecurrenceStorageAsync(for userId: String, retentionDays: Int) async -> Int
}

extension TaskStoring {
    @discardableResult
    func compactRecurrenceStorage(for userId: String) -> Int {
        compactRecurrenceStorage(for: userId, retentionDays: 7)
    }

    @discardableResult
    func compactRecurrenceStorageAsync(for userId: String) async -> Int {
        await compactRecurrenceStorageAsync(for: userId, retentionDays: 7)
    }

    @discardableResult
    func pruneTerminalRecurrenceOccurrences(for userId: String) -> Int {
        pruneTerminalRecurrenceOccurrences(for: userId, retentionDays: 7)
    }
}

extension TaskRepository: TaskStoring {
    public func warmLocalCache(for userId: String) async {
        _ = userId
        _ = await warmLocalCache(force: false)
    }
}
