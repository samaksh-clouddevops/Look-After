import Foundation
import GRDB
import LookAfterCore

/// On-device SQLite persistence for tasks — replaces `tasks.json` full-file rewrites.
public final class TaskSQLiteStore: @unchecked Sendable {

    public static let shared = TaskSQLiteStore()

    private let dbQueue: DatabaseQueue
    private let documentsDirectory: URL

    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    /// Production store at `Documents/tasks.sqlite`.
    public convenience init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.init(databaseURL: documents.appendingPathComponent("tasks.sqlite"), documentsDirectory: documents)
    }

    /// Isolated store for tests (`:memory:` skips JSON migration).
    public convenience init(inMemory: Bool) {
        if inMemory {
            let documents = FileManager.default.temporaryDirectory
            self.init(
                databaseURL: URL(fileURLWithPath: ":memory:"),
                documentsDirectory: documents,
                migrateFromJSON: false
            )
        } else {
            self.init()
        }
    }

    public init(databaseURL: URL, documentsDirectory: URL, migrateFromJSON: Bool = true) {
        self.documentsDirectory = documentsDirectory
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        do {
            dbQueue = try SQLiteStoreRecovery.openWithQuarantineFallback(
                databaseURL: databaseURL,
                configuration: configuration,
                storeName: "TaskSQLiteStore",
                prepare: Self.createSchema
            )
        } catch {
            fatalError("[TaskSQLiteStore] Failed to open database even after quarantine/recreate: \(error)")
        }

        if migrateFromJSON {
            do {
                try dbQueue.write { db in
                    try Self.migrateFromJSONIfNeeded(db, documentsDirectory: documentsDirectory)
                }
            } catch {
                // A corrupted legacy tasks.json should not brick an
                // otherwise-healthy database — skip migration and leave the
                // JSON file in place for manual recovery/inspection.
                print("[TaskSQLiteStore] JSON migration failed, skipping: \(error)")
            }
        }
    }

    // MARK: - Reads

    public func loadAll() throws -> [LifeTask] {
        try dbQueue.read { db in
            try TaskRecord.fetchAll(db).map { try $0.lifeTask() }
        }
    }

    public func loadAllAsync() async -> [LifeTask] {
        do {
            return try await dbQueue.read { db in
                try TaskRecord.fetchAll(db).map { try $0.lifeTask() }
            }
        } catch is CancellationError {
            // Superseded load — expected when bootstrap cancels an in-flight read.
            return []
        } catch {
            print("[TaskSQLiteStore] loadAllAsync failed: \(error)")
            return []
        }
    }

    // MARK: - Writes

    /// Fire-and-forget full replace — matches legacy JSON save semantics.
    public func replaceAllAsync(_ tasks: [LifeTask]) {
        let dbQueue = dbQueue
        Task.detached(priority: .userInitiated) {
            do {
                try await dbQueue.write { db in
                    try Self.replaceAll(tasks, in: db)
                }
            } catch {
                print("[TaskSQLiteStore] replaceAllAsync failed: \(error)")
            }
        }
    }

    /// Awaitable full replace for compaction and forced reload paths.
    public func replaceAllAwait(_ tasks: [LifeTask]) async {
        do {
            try await dbQueue.write { db in
                try Self.replaceAll(tasks, in: db)
            }
        } catch {
            print("[TaskSQLiteStore] replaceAllAwait failed: \(error)")
        }
    }

    /// Synchronous full replace — factory reset and tests.
    public func replaceAllSync(_ tasks: [LifeTask]) throws {
        try dbQueue.write { db in
            try Self.replaceAll(tasks, in: db)
        }
    }

    public func reset() throws {
        try replaceAllSync([])
    }

    /// Fire-and-forget single-row insert-or-update. Unlike `replaceAllAsync`, this never
    /// touches any other row, so it is safe to call even when the in-memory cache
    /// (`TaskRepository.cachedAll`) has not been warmed yet on a cold process — it cannot
    /// wipe previously persisted tasks belonging to this or any other user.
    public func upsertAsync(_ task: LifeTask) {
        let dbQueue = dbQueue
        Task.detached(priority: .userInitiated) {
            do {
                let record = try TaskRecord(task: task)
                try await dbQueue.write { db in
                    try record.save(db)
                }
            } catch {
                print("[TaskSQLiteStore] upsertAsync failed: \(error)")
            }
        }
    }

    /// Fire-and-forget single-row delete by id. Safe pre-warm for the same reason as `upsertAsync`.
    public func deleteRowAsync(_ id: String) {
        let dbQueue = dbQueue
        Task.detached(priority: .userInitiated) {
            do {
                try await dbQueue.write { db in
                    _ = try TaskRecord.deleteOne(db, key: id)
                }
            } catch {
                print("[TaskSQLiteStore] deleteRowAsync failed: \(error)")
            }
        }
    }

    // MARK: - Schema

    private static func createSchema(_ db: Database) throws {
        try db.create(table: TaskRecord.databaseTableName, ifNotExists: true) { table in
            table.column("id", .text).primaryKey()
            table.column("user_id", .text).notNull()
            table.column("status", .text).notNull()
            table.column("scheduled_date", .double)
            table.column("parent_task_id", .text)
            table.column("is_recurrence_template", .boolean).notNull().defaults(to: false)
            table.column("updated_at", .double).notNull()
            table.column("payload", .blob).notNull()
        }
        try db.create(index: "idx_tasks_user_id", on: TaskRecord.databaseTableName, columns: ["user_id"], ifNotExists: true)
        try db.create(
            index: "idx_tasks_scheduled_date",
            on: TaskRecord.databaseTableName,
            columns: ["scheduled_date"],
            ifNotExists: true
        )
        try db.create(
            index: "idx_tasks_parent_task_id",
            on: TaskRecord.databaseTableName,
            columns: ["parent_task_id"],
            ifNotExists: true
        )
        try db.create(index: "idx_tasks_status", on: TaskRecord.databaseTableName, columns: ["status"], ifNotExists: true)
    }

    private static func replaceAll(_ tasks: [LifeTask], in db: Database) throws {
        try TaskRecord.deleteAll(db)
        for task in tasks {
            try TaskRecord(task: task).insert(db)
        }
    }

    // MARK: - JSON migration

    private static func migrateFromJSONIfNeeded(_ db: Database, documentsDirectory: URL) throws {
        let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tasks") ?? 0
        guard count == 0 else { return }

        let jsonURL = documentsDirectory.appendingPathComponent("tasks.json")
        guard FileManager.default.fileExists(atPath: jsonURL.path) else { return }

        let data = try Data(contentsOf: jsonURL)
        let tasks = try jsonDecoder.decode([LifeTask].self, from: data)
        guard !tasks.isEmpty else { return }

        for task in tasks {
            try TaskRecord(task: task).insert(db)
        }

        let backupURL = documentsDirectory.appendingPathComponent("tasks.json.migrated")
        try? FileManager.default.removeItem(at: backupURL)
        try FileManager.default.moveItem(at: jsonURL, to: backupURL)
        print("[TaskSQLiteStore] migrated \(tasks.count) tasks from tasks.json → tasks.sqlite")
    }

    static func encode(_ task: LifeTask) throws -> Data {
        try jsonEncoder.encode(task)
    }

    static func decode(_ data: Data) throws -> LifeTask {
        try jsonDecoder.decode(LifeTask.self, from: data)
    }
}

// MARK: - Row mapping

private struct TaskRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "tasks"

    var id: String
    var userId: String
    var status: String
    var scheduledDate: Double?
    var parentTaskId: String?
    var isRecurrenceTemplate: Bool
    var updatedAt: Double
    var payload: Data

    enum Columns: String, ColumnExpression {
        case id
        case userId = "user_id"
        case status
        case scheduledDate = "scheduled_date"
        case parentTaskId = "parent_task_id"
        case isRecurrenceTemplate = "is_recurrence_template"
        case updatedAt = "updated_at"
        case payload
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case status
        case scheduledDate = "scheduled_date"
        case parentTaskId = "parent_task_id"
        case isRecurrenceTemplate = "is_recurrence_template"
        case updatedAt = "updated_at"
        case payload
    }

    init(task: LifeTask) throws {
        id = task.id
        userId = task.userId
        status = task.status.rawValue
        scheduledDate = task.scheduledDate?.timeIntervalSince1970
        parentTaskId = task.parentTaskId
        isRecurrenceTemplate = task.isRecurrenceTemplate ?? false
        updatedAt = task.updatedAt.timeIntervalSince1970
        payload = try TaskSQLiteStore.encode(task)
    }

    func lifeTask() throws -> LifeTask {
        try TaskSQLiteStore.decode(payload)
    }
}
