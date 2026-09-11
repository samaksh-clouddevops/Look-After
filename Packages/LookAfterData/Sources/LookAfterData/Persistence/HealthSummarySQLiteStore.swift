import Foundation
import GRDB
import LookAfterCore

/// On-device SQLite persistence for health summaries (H3). Migrates from `health_summaries.json`.
public final class HealthSummarySQLiteStore: @unchecked Sendable {
    public static let shared = HealthSummarySQLiteStore()

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

    public convenience init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.init(databaseURL: documents.appendingPathComponent("health_summaries.sqlite"), documentsDirectory: documents)
    }

    public convenience init(inMemory: Bool) {
        if inMemory {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("health-\(UUID().uuidString).sqlite")
            self.init(
                databaseURL: url,
                documentsDirectory: url.deletingLastPathComponent(),
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
            dbQueue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
            try dbQueue.write { db in
                try Self.createSchema(db)
                if migrateFromJSON {
                    try Self.migrateFromJSONIfNeeded(db, documentsDirectory: documentsDirectory)
                }
            }
            if databaseURL.path != ":memory:" {
                try? FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: databaseURL.path
                )
            }
        } catch {
            fatalError("[HealthSummarySQLiteStore] Failed to open database: \(error)")
        }
    }

    public func loadAll() throws -> [HealthSummary] {
        try dbQueue.read { db in
            try HealthSummaryRecord.fetchAll(db).map { try $0.summary() }
        }
    }

    public func upsert(_ summary: HealthSummary) throws {
        try dbQueue.write { db in
            try HealthSummaryRecord(summary: summary).save(db)
        }
    }

    public func replaceAll(_ summaries: [HealthSummary]) throws {
        try dbQueue.write { db in
            try HealthSummaryRecord.deleteAll(db)
            for summary in summaries {
                try HealthSummaryRecord(summary: summary).insert(db)
            }
        }
    }

    public func reset() throws {
        try replaceAll([])
    }

    private static func createSchema(_ db: Database) throws {
        try db.create(table: HealthSummaryRecord.databaseTableName, ifNotExists: true) { table in
            table.column("id", .text).primaryKey()
            table.column("user_id", .text).notNull()
            table.column("date", .double).notNull()
            table.column("updated_at", .double).notNull()
            table.column("payload", .blob).notNull()
        }
        try db.create(index: "idx_health_user_id", on: HealthSummaryRecord.databaseTableName, columns: ["user_id"], ifNotExists: true)
        try db.create(index: "idx_health_date", on: HealthSummaryRecord.databaseTableName, columns: ["date"], ifNotExists: true)
    }

    private static func migrateFromJSONIfNeeded(_ db: Database, documentsDirectory: URL) throws {
        let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM health_summaries") ?? 0
        guard count == 0 else { return }

        let jsonURL = documentsDirectory.appendingPathComponent("health_summaries.json")
        guard FileManager.default.fileExists(atPath: jsonURL.path) else { return }

        let data = try Data(contentsOf: jsonURL)
        let summaries = try jsonDecoder.decode([HealthSummary].self, from: data)
        guard !summaries.isEmpty else { return }

        for summary in summaries {
            try HealthSummaryRecord(summary: summary).insert(db)
        }

        let backupURL = documentsDirectory.appendingPathComponent("health_summaries.json.migrated")
        try? FileManager.default.removeItem(at: backupURL)
        try FileManager.default.moveItem(at: jsonURL, to: backupURL)
        print("[HealthSummarySQLiteStore] migrated \(summaries.count) summaries from JSON → SQLite")
    }

    static func encode(_ summary: HealthSummary) throws -> Data {
        try jsonEncoder.encode(summary)
    }

    static func decode(_ data: Data) throws -> HealthSummary {
        try jsonDecoder.decode(HealthSummary.self, from: data)
    }
}

private struct HealthSummaryRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "health_summaries"

    var id: String
    var userId: String
    var date: Double
    var updatedAt: Double
    var payload: Data

    enum Columns: String, ColumnExpression {
        case id
        case userId = "user_id"
        case date
        case updatedAt = "updated_at"
        case payload
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case updatedAt = "updated_at"
        case payload
    }

    init(summary: HealthSummary) throws {
        id = summary.id
        userId = summary.userId
        date = summary.date.timeIntervalSince1970
        updatedAt = Date().timeIntervalSince1970
        payload = try HealthSummarySQLiteStore.encode(summary)
    }

    func summary() throws -> HealthSummary {
        try HealthSummarySQLiteStore.decode(payload)
    }
}
