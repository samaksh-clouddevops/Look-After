import Foundation
import LookAfterCore

/// Single published source for task lists — wraps `TaskRepository` and republishes snapshots.
@MainActor
public final class TaskStore: ObservableObject, TaskStoring {
    public static let shared = TaskStore()

    @Published public private(set) var snapshot: TaskListSnapshot = TaskListSnapshot(active: [], completedToday: [])
    @Published public private(set) var allTasks: [LifeTask] = []

    private let taskRepo: TaskRepository
    private var lastUserId: String = ""

    public init(taskRepo: TaskRepository? = nil) {
        self.taskRepo = taskRepo ?? TaskRepository()
    }

    // MARK: - Snapshot refresh

    /// Off-main disk hydrate into TaskRepository cache, then publish local snapshot.
    /// Prefer this over bare `refreshLocal` on cold launch.
    public func warmLocalCache(for userId: String) async {
        await warmLocalCache(userId: userId, force: false)
    }

    public func warmLocalCache(userId: String, force: Bool = false) async {
        _ = await taskRepo.warmLocalCache(force: force)
        guard !userId.isEmpty else { return }
        refreshLocal(userId: userId)
    }

    public func refreshLocal(userId: String) {
        guard !userId.isEmpty else { return }
        lastUserId = userId
        let snap = taskRepo.localSnapshot(for: userId)
        snapshot = snap
        allTasks = taskRepo.localAllTasks(for: userId)
    }

    @discardableResult
    public func loadRemote(userId: String) async throws -> TaskListSnapshot {
        guard !userId.isEmpty else { return snapshot }
        lastUserId = userId
        await taskRepo.warmLocalCache()
        _ = try await taskRepo.getTaskLists(for: userId)
        refreshLocal(userId: userId)
        return snapshot
    }

    public func resetLocalStore() {
        taskRepo.resetLocalStore()
        snapshot = TaskListSnapshot(active: [], completedToday: [])
        allTasks = []
        notifyChange()
    }

    public func enterFreshInstallMode() {
        taskRepo.enterFreshInstallMode()
        snapshot = TaskListSnapshot(active: [], completedToday: [])
        allTasks = []
    }

    public func exitFreshInstallMode() {
        taskRepo.exitFreshInstallMode()
    }

    public func reassignTasks(from oldUserId: String, to newUserId: String) {
        taskRepo.reassignTasks(from: oldUserId, to: newUserId)
        if !lastUserId.isEmpty {
            refreshLocal(userId: lastUserId)
        } else if !newUserId.isEmpty {
            refreshLocal(userId: newUserId)
        }
        notifyChange()
    }

    // MARK: - TaskStoring

    public func localSnapshot(for userId: String) -> TaskListSnapshot {
        taskRepo.localSnapshot(for: userId)
    }

    public func localAllTasks(for userId: String) -> [LifeTask] {
        taskRepo.localAllTasks(for: userId)
    }

    public func getTaskLists(for userId: String) async throws -> TaskListSnapshot {
        let snap = try await taskRepo.getTaskLists(for: userId)
        refreshLocal(userId: userId)
        return snap
    }

    public func getActive(for userId: String) async throws -> [LifeTask] {
        try await getTaskLists(for: userId).active
    }

    public func getCompletedToday(for userId: String) async throws -> [LifeTask] {
        try await getTaskLists(for: userId).completedToday
    }

    public func getAll(for userId: String) async throws -> [LifeTask] {
        let tasks = try await taskRepo.getAll(for: userId)
        refreshLocal(userId: userId)
        return tasks
    }

    public func create(_ task: LifeTask) async throws {
        try await taskRepo.create(task)
        republishAfterMutation(userId: task.userId)
    }

    public func update(_ task: LifeTask) async throws {
        try await taskRepo.update(task)
        republishAfterMutation(userId: task.userId)
    }

    public func updateMany(_ tasks: [LifeTask]) async throws {
        try await taskRepo.updateMany(tasks)
        if let userId = tasks.first?.userId, !userId.isEmpty {
            republishAfterMutation(userId: userId)
        } else {
            republishAfterMutation(userId: lastUserId)
        }
    }

    public func delete(_ id: String) async throws {
        try await taskRepo.delete(id)
        republishAfterMutation(userId: lastUserId)
    }

    @discardableResult
    public func pruneTerminalRecurrenceOccurrences(for userId: String, retentionDays: Int = 7) -> Int {
        compactRecurrenceStorage(for: userId, retentionDays: retentionDays)
    }

    @discardableResult
    public func compactRecurrenceStorage(for userId: String, retentionDays: Int = 7) -> Int {
        let removed = taskRepo.compactRecurrenceStorage(for: userId, retentionDays: retentionDays)
        if removed > 0, !userId.isEmpty {
            refreshLocal(userId: userId)
            notifyChange()
        }
        return removed
    }

    @discardableResult
    public func compactRecurrenceStorageAsync(for userId: String, retentionDays: Int = 7) async -> Int {
        let removed = await taskRepo.compactRecurrenceStorageAsync(for: userId, retentionDays: retentionDays)
        if removed > 0, !userId.isEmpty {
            refreshLocal(userId: userId)
            notifyChange()
        }
        return removed
    }

    // MARK: - Private

    private var notificationSuppressionDepth = 0

    /// Coalesce TaskStore notifications during batched schedule sync.
    public func beginSuppressingNotifications() {
        notificationSuppressionDepth += 1
    }

    public func endSuppressingNotifications() {
        notificationSuppressionDepth = max(0, notificationSuppressionDepth - 1)
    }

    private func republishAfterMutation(userId: String) {
        let uid = userId.isEmpty ? lastUserId : userId
        if !uid.isEmpty {
            refreshLocal(userId: uid)
        }
        notifyChange()
    }

    private func notifyChange() {
        guard notificationSuppressionDepth == 0 else { return }
        NotificationCenter.default.post(name: .taskListDidChange, object: nil)
    }
}
