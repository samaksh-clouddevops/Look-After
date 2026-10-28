import Foundation
import LookAfterCore
import LookAfterData

/// Isolated, on-disk production SQLite with a controllable snapshot clock and
/// deterministic write failures. Reopening reconstructs both the store and VM.
@MainActor
final class SimulationStore: TaskStoring {
    let directory: URL
    var now: Date
    var failNextWrite = false
    var writesBeforeFailure: Int?
    private let sqlite: TaskSQLiteStore
    private var rows: [LifeTask]

    init(directory: URL, now: Date) throws {
        self.directory = directory
        self.now = now
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        sqlite = TaskSQLiteStore(
            databaseURL: directory.appendingPathComponent("tasks.sqlite"),
            documentsDirectory: directory, migrateFromJSON: false
        )
        rows = try sqlite.loadAll()
    }

    func warmLocalCache(for userId: String) async { rows = (try? sqlite.loadAll()) ?? rows }
    func localAllTasks(for userId: String) -> [LifeTask] {
        rows = (try? sqlite.loadAll()) ?? rows
        return rows.filter { $0.userId == userId }
    }
    func localSnapshot(for userId: String) -> TaskListSnapshot {
        .make(from: localAllTasks(for: userId), calendar: .current, referenceDate: now)
    }
    func getTaskLists(for userId: String) async throws -> TaskListSnapshot { localSnapshot(for: userId) }
    func getAll(for userId: String) async throws -> [LifeTask] { localAllTasks(for: userId) }
    func getActive(for userId: String) async throws -> [LifeTask] { localSnapshot(for: userId).active }
    func getCompletedToday(for userId: String) async throws -> [LifeTask] { localSnapshot(for: userId).completedToday }
    func create(_ task: LifeTask) async throws {
        try write(sqlite.loadAll().filter { $0.id != task.id } + [task])
    }
    func update(_ task: LifeTask) async throws { try await create(task) }
    func updateMany(_ updates: [LifeTask]) async throws {
        let ids = Set(updates.map(\.id))
        try write(sqlite.loadAll().filter { !ids.contains($0.id) } + updates)
    }
    func delete(_ id: String, userId: String) async throws { try write(sqlite.loadAll().filter { $0.id != id }) }
    func pruneTerminalRecurrenceOccurrences(for userId: String, retentionDays: Int) -> Int { 0 }
    func compactRecurrenceStorage(for userId: String, retentionDays: Int) -> Int { 0 }
    func compactRecurrenceStorageAsync(for userId: String, retentionDays: Int) async -> Int { 0 }

    private func write(_ next: [LifeTask]) throws {
        if failNextWrite || writesBeforeFailure == 0 {
            failNextWrite = false
            writesBeforeFailure = nil
            throw CocoaError(.fileWriteOutOfSpace)
        }
        if let remaining = writesBeforeFailure { writesBeforeFailure = remaining - 1 }
        try sqlite.replaceAllSync(next)
        rows = next
    }
}
