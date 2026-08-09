import Foundation
import GRDB
import LookAfterCore
import os

/// On-device SQLite persistence for tasks — replaces `tasks.json` full-file rewrites.
public final class TaskSQLiteStore: @unchecked Sendable {

    public static let shared = TaskSQLiteStore()

    private let dbQueue: DatabaseQueue
    private let documentsDirectory: URL
    private static let logger = Logger(subsystem: "com.lookafter.app", category: "TaskSQLiteStore")

    public enum StoreError: Error, LocalizedError {
        case openFailed(String)
        case writeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .openFailed(let message): return "Could not open task database: \(message)"
            case .writeFailed(let message): return "Could not save tasks: \(message)"
            }
        }
    }

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
        self.dbQueue = Self.openQueue(
            databaseURL: databaseURL,
            documentsDirectory: documentsDirectory,
            migrateFromJSON: migrateFromJSON
        )
    }

    /// Opens the DB; on corruption quarantines the file and opens a fresh empty store (no crash).
    private static func openQueue(
        databaseURL: URL,
        documentsDirectory: URL,
        migrateFromJSON: Bool
    ) -> DatabaseQueue {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let isMemory = databaseURL.path == ":memory:"

        func makeQueue(at url: URL, migrate: Bool) throws -> DatabaseQueue {
            let queue = try DatabaseQueue(path: url.path, configuration: configuration)
            try queue.write { db in
                try createSchema(db)
                if migrate {
                    try migrateFromJSONIfNeeded(db, documentsDirectory: documentsDirectory)
                }
            }
            return queue
        }

        do {
            return try makeQueue(at: databaseURL, migrate: migrateFromJSON)
        } catch {
            logger.error("Primary task DB open failed: \(error.localizedDescription, privacy: .public)")
            if !isMemory {
                quarantineCorruptDatabase(at: databaseURL)
                if let recovered = try? makeQueue(at: databaseURL, migrate: false) {
                    return recovered
                }
                logger.error("Fresh on-disk task DB open failed; falling back to memory")
            }
            // Always-available empty store so cold launch never crashes on I/O failure.
            if let memory = try? makeQueue(at: URL(fileURLWithPath: ":memory:"), migrate: false) {
                return memory
            }
            // Bare memory queue — schema is recreated on first successful write path if needed.
            do {
                let bare = try DatabaseQueue(path: ":memory:", configuration: configuration)
                try? bare.write { db in try createSchema(db) }
                return bare
            } catch {
                // Absolute last resort: GRDB default in-memory database.
                // swiftlint:disable:next force_try
                return try! DatabaseQueue()
            }
        }
    }

    private static func quarantineCorruptDatabase(at url: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        let quarantine = url.deletingLastPathComponent()
            .appendingPathComponent("tasks.sqlite.corrupt-\(stamp)")
        try? fm.removeItem(at: quarantine)
        do {
            try fm.moveItem(at: url, to: quarantine)
            logger.fault("Quarantined corrupt task database to \(quarantine.lastPathComponent, privacy: .public)")
        } catch {
            try? fm.removeItem(at: url)
            logger.fault("Removed unreadable task database after quarantine failed")
        }
        // Sidecars
        for suffix in ["-wal", "-shm"] {
            let side = URL(fileURLWithPath: url.path + suffix)
            try? fm.removeItem(at: side)
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
        } catch {
            logger.error("loadAllAsync failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Writes

    /// Fire-and-forget full replace — prefer `replaceAllAwait` on mutation paths.
    public func replaceAllAsync(_ tasks: [LifeTask]) {
        let dbQueue = dbQueue
        Task.detached(priority: .userInitiated) {
            do {
                try await dbQueue.write { db in
                    try Self.replaceAll(tasks, in: db)
                }
            } catch {
                Self.logger.error("replaceAllAsync failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Awaitable full replace — throws on write failure so callers can roll back UI.
    public func replaceAllAwait(_ tasks: [LifeTask]) async throws {
        do {
            try await dbQueue.write { db in
                try Self.replaceAll(tasks, in: db)
            }
        } catch {
            logger.error("replaceAllAwait failed: \(error.localizedDescription, privacy: .public)")
            throw StoreError.writeFailed(error.localizedDescription)
        }
    }

    /// Synchronous full replace — factory reset and tests.
    public func replaceAllSync(_ tasks: [LifeTask]) throws {
        do {
            try dbQueue.write { db in
                try Self.replaceAll(tasks, in: db)
            }
        } catch {
            throw StoreError.writeFailed(error.localizedDescription)
        }
    }

    public func reset() throws {
        try replaceAllSync([])
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
