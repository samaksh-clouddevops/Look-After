import Foundation
import GRDB
import LookAfterCore
import os

/// Generic per-collection SQLite store for Codable module entities (Phase 2 WP 2.4).
/// Payload is full JSON; indexes support user filter + optional sort field.
public final class JSONEntitySQLiteStore: @unchecked Sendable {

    public static let sharedBills = JSONEntitySQLiteStore(filename: "module_bills.sqlite", table: "bills")
    public static let sharedShopping = JSONEntitySQLiteStore(filename: "module_shopping.sqlite", table: "shopping_items")
    public static let sharedRelationships = JSONEntitySQLiteStore(filename: "module_relationships.sqlite", table: "relationships")
    public static let sharedJournal = JSONEntitySQLiteStore(filename: "module_journal.sqlite", table: "journal_entries")

    private let dbQueue: DatabaseQueue
    private let table: String
    private let logger = Logger(subsystem: "com.lookafter.app", category: "JSONEntitySQLite")

    public init(filename: String, table: String) {
        self.table = table
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(filename)
        do {
            dbQueue = try DatabaseQueue(path: url.path)
            try Self.migrate(dbQueue, table: table)
        } catch {
            logger.error("open \(filename, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            // swiftlint:disable:next force_try
            dbQueue = try! DatabaseQueue()
            try? Self.migrate(dbQueue, table: table)
        }
    }

    /// In-memory for tests.
    public init(inMemoryTable table: String) {
        self.table = table
        // swiftlint:disable:next force_try
        dbQueue = try! DatabaseQueue()
        try? Self.migrate(dbQueue, table: table)
    }

    private static func migrate(_ dbQueue: DatabaseQueue, table: String) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_\(table)") { db in
            try db.create(table: table, ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("user_id", .text).notNull()
                t.column("payload", .blob).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(index: "idx_\(table)_user", on: table, columns: ["user_id"], ifNotExists: true)
        }
        try migrator.migrate(dbQueue)
    }

    public func upsert<T: Encodable>(id: String, userId: String, value: T) throws {
        let data = try SharedFormatters.jsonEncoderSeconds.encode(value)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO \(table) (id, user_id, payload, updated_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  user_id = excluded.user_id,
                  payload = excluded.payload,
                  updated_at = excluded.updated_at
                """,
                arguments: [id, userId, data, Date()]
            )
        }
    }

    public func delete(id: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM \(table) WHERE id = ?", arguments: [id])
        }
    }

    public func loadAll<T: Decodable>(as type: T.Type, userId: String? = nil) throws -> [T] {
        try dbQueue.read { db in
            let rows: [Row]
            if let userId, !userId.isEmpty {
                rows = try Row.fetchAll(
                    db,
                    sql: "SELECT payload FROM \(table) WHERE user_id = ? OR user_id = '' ORDER BY updated_at DESC",
                    arguments: [userId]
                )
            } else {
                rows = try Row.fetchAll(db, sql: "SELECT payload FROM \(table) ORDER BY updated_at DESC")
            }
            return rows.compactMap { row in
                guard let data: Data = row["payload"] else { return nil }
                return try? SharedFormatters.jsonDecoderSeconds.decode(T.self, from: data)
            }
        }
    }

    public func replaceAll<T: Encodable>(userId: String, items: [(id: String, value: T)]) throws {
        try dbQueue.write { db in
            if userId.isEmpty {
                try db.execute(sql: "DELETE FROM \(table)")
            } else {
                try db.execute(sql: "DELETE FROM \(table) WHERE user_id = ?", arguments: [userId])
            }
            let now = Date()
            for item in items {
                let data = try SharedFormatters.jsonEncoderSeconds.encode(item.value)
                try db.execute(
                    sql: "INSERT INTO \(table) (id, user_id, payload, updated_at) VALUES (?, ?, ?, ?)",
                    arguments: [item.id, userId, data, now]
                )
            }
        }
    }

    /// Import from LocalPersistence JSON filename if SQLite empty.
    public func migrateFromJSONIfNeeded<T: Codable>(
        as type: T.Type,
        filename: String,
        id: (T) -> String,
        userId: (T) -> String,
        local: LocalPersistenceManager = .shared
    ) {
        let existing = (try? loadAll(as: type)) ?? []
        guard existing.isEmpty else { return }
        let legacy = local.load([T].self, filename: filename)
        guard !legacy.isEmpty else { return }
        for item in legacy {
            try? upsert(id: id(item), userId: userId(item), value: item)
        }
    }
}
