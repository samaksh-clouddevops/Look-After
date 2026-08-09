import Foundation
import GRDB
import LookAfterCore
import os

/// Local-first inbox persistence (Phase 2 WP 2.2).
public final class InboxSQLiteStore: @unchecked Sendable {

    public static let shared = InboxSQLiteStore()

    private let dbQueue: DatabaseQueue
    private let logger = Logger(subsystem: "com.lookafter.app", category: "InboxSQLite")

    public convenience init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.init(databaseURL: docs.appendingPathComponent("inbox.sqlite"))
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
            logger.error("Inbox DB open failed, memory fallback: \(error.localizedDescription, privacy: .public)")
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
        migrator.registerMigration("v1_inbox") { db in
            try db.create(table: "inbox_items", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("user_id", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("status", .text).notNull()
                t.column("payload", .blob).notNull()
            }
            try db.create(
                index: "idx_inbox_user_created",
                on: "inbox_items",
                columns: ["user_id", "created_at"],
                ifNotExists: true
            )
        }
        try migrator.migrate(dbQueue)
    }

    public func upsert(_ item: InboxItem) throws {
        let data = try SharedFormatters.jsonEncoderSeconds.encode(item)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO inbox_items (id, user_id, created_at, status, payload)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  user_id = excluded.user_id,
                  created_at = excluded.created_at,
                  status = excluded.status,
                  payload = excluded.payload
                """,
                arguments: [
                    item.id,
                    item.userId,
                    item.createdAt,
                    item.status.rawValue,
                    data,
                ]
            )
        }
    }

    public func delete(id: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM inbox_items WHERE id = ?", arguments: [id])
        }
    }

    public func loadAll(userId: String) throws -> [InboxItem] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT payload FROM inbox_items
                WHERE user_id = ?
                ORDER BY created_at DESC
                """,
                arguments: [userId]
            )
            return rows.compactMap { row in
                guard let data: Data = row["payload"] else { return nil }
                return try? SharedFormatters.jsonDecoderSeconds.decode(InboxItem.self, from: data)
            }
        }
    }

    public func loadUnprocessed(userId: String) throws -> [InboxItem] {
        try loadAll(userId: userId).filter { $0.status == .unprocessed }
    }

    public func replaceAll(userId: String, items: [InboxItem]) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM inbox_items WHERE user_id = ?", arguments: [userId])
            for item in items {
                let data = try SharedFormatters.jsonEncoderSeconds.encode(item)
                try db.execute(
                    sql: """
                    INSERT INTO inbox_items (id, user_id, created_at, status, payload)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    arguments: [item.id, item.userId, item.createdAt, item.status.rawValue, data]
                )
            }
        }
    }
}
