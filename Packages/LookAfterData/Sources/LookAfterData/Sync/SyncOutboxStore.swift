import Foundation
import GRDB
import LookAfterCore
import os

/// SQLite-backed durable queue for cloud mutations (ADR-006).
public final class SyncOutboxStore: @unchecked Sendable {

    public static let shared = SyncOutboxStore()

    private let dbQueue: DatabaseQueue
    private let logger = Logger(subsystem: "com.lookafter.app", category: "SyncOutbox")

    public enum StoreError: Error, LocalizedError {
        case writeFailed(String)
        public var errorDescription: String? {
            switch self {
            case .writeFailed(let m): return m
            }
        }
    }

    public convenience init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.init(databaseURL: docs.appendingPathComponent("sync_outbox.sqlite"))
    }

    public convenience init(inMemory: Bool) {
        if inMemory {
            // swiftlint:disable:next force_try
            let q = try! DatabaseQueue()
            try? Self.migrate(q)
            self.init(dbQueue: q)
        } else {
            self.init()
        }
    }

    public init(databaseURL: URL) {
        do {
            dbQueue = try DatabaseQueue(path: databaseURL.path)
            try Self.migrate(dbQueue)
        } catch {
            logger.error("Outbox open failed, falling back to memory: \(error.localizedDescription, privacy: .public)")
            // swiftlint:disable:next force_try
            dbQueue = try! DatabaseQueue()
            try? Self.migrate(dbQueue)
        }
    }

    private init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    private static func migrate(_ dbQueue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_outbox") { db in
            try db.create(table: "sync_outbox", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("user_id", .text).notNull()
                t.column("entity_type", .text).notNull()
                t.column("entity_id", .text).notNull()
                t.column("operation", .text).notNull()
                t.column("payload", .blob).notNull()
                t.column("attempts", .integer).notNull().defaults(to: 0)
                t.column("status", .text).notNull()
                t.column("next_attempt_at", .datetime).notNull()
                t.column("last_error", .text)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(
                index: "idx_outbox_drain",
                on: "sync_outbox",
                columns: ["user_id", "status", "next_attempt_at"],
                ifNotExists: true
            )
        }
        try migrator.migrate(dbQueue)
    }

    // MARK: - API

    public func enqueue(_ record: SyncOutboxRecord) throws {
        try dbQueue.write { db in
            // Coalesce: replace pending row for same user/entity/op.
            try db.execute(
                sql: """
                DELETE FROM sync_outbox
                WHERE user_id = ? AND entity_type = ? AND entity_id = ?
                  AND operation = ? AND status IN ('pending', 'failed')
                """,
                arguments: [
                    record.userId,
                    record.entityType.rawValue,
                    record.entityId,
                    record.operation.rawValue,
                ]
            )
            try OutboxRow(record: record).insert(db)
        }
    }

    public func pendingCount(userId: String) throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*) FROM sync_outbox
                WHERE user_id = ? AND status IN ('pending', 'failed', 'inFlight')
                """,
                arguments: [userId]
            ) ?? 0
        }
    }

    public func dequeueReady(userId: String, limit: Int = 20, now: Date = Date()) throws -> [SyncOutboxRecord] {
        try dbQueue.write { db in
            let rows = try OutboxRow.fetchAll(
                db,
                sql: """
                SELECT * FROM sync_outbox
                WHERE user_id = ?
                  AND status IN ('pending', 'failed')
                  AND next_attempt_at <= ?
                ORDER BY created_at ASC
                LIMIT ?
                """,
                arguments: [userId, now, limit]
            )
            for row in rows {
                try db.execute(
                    sql: "UPDATE sync_outbox SET status = 'inFlight', updated_at = ? WHERE id = ?",
                    arguments: [now, row.id]
                )
            }
            return rows.map { $0.record(statusOverride: .inFlight) }
        }
    }

    public func markSucceeded(id: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM sync_outbox WHERE id = ?", arguments: [id])
        }
    }

    public func markFailed(id: String, error: String, attempts: Int, nextAttemptAt: Date, dead: Bool) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE sync_outbox
                SET status = ?, attempts = ?, next_attempt_at = ?, last_error = ?, updated_at = ?
                WHERE id = ?
                """,
                arguments: [
                    dead ? SyncOutboxStatus.dead.rawValue : SyncOutboxStatus.failed.rawValue,
                    attempts,
                    nextAttemptAt,
                    error,
                    Date(),
                    id,
                ]
            )
        }
    }

    public func resetInFlightToPending(userId: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE sync_outbox SET status = 'pending', updated_at = ?
                WHERE user_id = ? AND status = 'inFlight'
                """,
                arguments: [Date(), userId]
            )
        }
    }
}

// MARK: - GRDB row

private struct OutboxRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "sync_outbox"

    var id: String
    var userId: String
    var entityType: String
    var entityId: String
    var operation: String
    var payload: Data
    var attempts: Int
    var status: String
    var nextAttemptAt: Date
    var lastError: String?
    var createdAt: Date
    var updatedAt: Date

    enum Columns: String, ColumnExpression {
        case id, payload, attempts, status
        case userId = "user_id"
        case entityType = "entity_type"
        case entityId = "entity_id"
        case operation
        case nextAttemptAt = "next_attempt_at"
        case lastError = "last_error"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    enum CodingKeys: String, CodingKey {
        case id, payload, attempts, status, operation
        case userId = "user_id"
        case entityType = "entity_type"
        case entityId = "entity_id"
        case nextAttemptAt = "next_attempt_at"
        case lastError = "last_error"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(record: SyncOutboxRecord) {
        id = record.id
        userId = record.userId
        entityType = record.entityType.rawValue
        entityId = record.entityId
        operation = record.operation.rawValue
        payload = record.payloadJSON
        attempts = record.attempts
        status = record.status.rawValue
        nextAttemptAt = record.nextAttemptAt
        lastError = record.lastError
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    func record(statusOverride: SyncOutboxStatus? = nil) -> SyncOutboxRecord {
        SyncOutboxRecord(
            id: id,
            userId: userId,
            entityType: SyncOutboxEntityType(rawValue: entityType) ?? .task,
            entityId: entityId,
            operation: SyncOutboxOperation(rawValue: operation) ?? .upsert,
            payloadJSON: payload,
            attempts: attempts,
            status: statusOverride ?? SyncOutboxStatus(rawValue: status) ?? .pending,
            nextAttemptAt: nextAttemptAt,
            lastError: lastError,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
