import Foundation
import GRDB
import LookAfterCore
import os

/// Local health summaries in SQLite (Phase 2 WP 2.3). JSON file remains fallback for migration.
public final class HealthSummarySQLiteStore: @unchecked Sendable {

    public static let shared = HealthSummarySQLiteStore()

    private let dbQueue: DatabaseQueue
    private let logger = Logger(subsystem: "com.lookafter.app", category: "HealthSummarySQLite")
    private var didMigrateFromJSON = false

    public convenience init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.init(databaseURL: docs.appendingPathComponent("health_summaries.sqlite"))
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
            logger.error("Health DB open failed: \(error.localizedDescription, privacy: .public)")
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
        migrator.registerMigration("v1_health") { db in
            try db.create(table: "health_summaries", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("user_id", .text).notNull()
                t.column("date", .datetime).notNull()
                t.column("payload", .blob).notNull()
            }
            try db.create(
                index: "idx_health_user_date",
                on: "health_summaries",
                columns: ["user_id", "date"],
                ifNotExists: true
            )
        }
        try migrator.migrate(dbQueue)
    }

    /// One-time import from legacy `health_summaries` JSON via LocalPersistenceManager.
    public func migrateFromJSONIfNeeded(using local: LocalPersistenceManager = .shared) {
        guard !didMigrateFromJSON else { return }
        didMigrateFromJSON = true
        let existing = (try? loadAll()) ?? []
        guard existing.isEmpty else { return }
        let legacy = local.load([HealthSummary].self, filename: "health_summaries")
        guard !legacy.isEmpty else { return }
        do {
            try replaceAll(legacy)
            logger.info("Migrated \(legacy.count, privacy: .public) health summaries from JSON")
        } catch {
            logger.error("Health JSON migration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func upsert(_ summary: HealthSummary) throws {
        let data = try SharedFormatters.jsonEncoderSeconds.encode(summary)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO health_summaries (id, user_id, date, payload)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  user_id = excluded.user_id,
                  date = excluded.date,
                  payload = excluded.payload
                """,
                arguments: [summary.id, summary.userId, summary.date, data]
            )
        }
    }

    public func loadAll() throws -> [HealthSummary] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT payload FROM health_summaries ORDER BY date DESC")
            return rows.compactMap { row in
                guard let data: Data = row["payload"] else { return nil }
                return try? SharedFormatters.jsonDecoderSeconds.decode(HealthSummary.self, from: data)
            }
        }
    }

    public func replaceAll(_ items: [HealthSummary]) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM health_summaries")
            for summary in items {
                let data = try SharedFormatters.jsonEncoderSeconds.encode(summary)
                try db.execute(
                    sql: "INSERT INTO health_summaries (id, user_id, date, payload) VALUES (?, ?, ?, ?)",
                    arguments: [summary.id, summary.userId, summary.date, data]
                )
            }
        }
    }

    public func reassign(from oldUserId: String, to newUserId: String) throws {
        var all = try loadAll()
        var changed = false
        for i in all.indices where all[i].userId == oldUserId {
            all[i].userId = newUserId
            if all[i].id.hasPrefix("\(oldUserId)-") {
                all[i].id = all[i].id.replacingOccurrences(of: oldUserId, with: newUserId)
            }
            changed = true
        }
        if changed {
            try replaceAll(all)
        }
    }
}
