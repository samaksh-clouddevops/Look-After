import Foundation
import GRDB
import LookAfterCore

/// On-device SQLite persistence for inbox items (H2 — local-first).
public final class InboxSQLiteStore: @unchecked Sendable {
    public static let shared = InboxSQLiteStore()

    private let dbQueue: DatabaseQueue

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
        self.init(databaseURL: documents.appendingPathComponent("inbox.sqlite"))
    }

    public convenience init(inMemory: Bool) {
        if inMemory {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("inbox-\(UUID().uuidString).sqlite")
            self.init(databaseURL: url)
        } else {
            self.init()
        }
    }

    public init(databaseURL: URL) {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        do {
            dbQueue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
            try dbQueue.write { db in
                try Self.createSchema(db)
            }
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: databaseURL.path
            )
        } catch {
            fatalError("[InboxSQLiteStore] Failed to open database: \(error)")
        }
    }

    public func loadAll(for userId: String) throws -> [InboxItem] {
        try dbQueue.read { db in
            let records: [InboxRecord]
            if userId.isEmpty {
                records = try InboxRecord.fetchAll(db)
            } else {
                records = try InboxRecord
                    .filter(InboxRecord.Columns.userId == userId || InboxRecord.Columns.userId == "")
                    .fetchAll(db)
            }
            return try records.map { try $0.inboxItem() }
                .sorted { $0.createdAt > $1.createdAt }
        }
    }

    public func upsert(_ item: InboxItem) throws {
        try dbQueue.write { db in
            try InboxRecord(item: item).save(db)
        }
    }

    public func delete(id: String) throws {
        try dbQueue.write { db in
            _ = try InboxRecord.deleteOne(db, key: id)
        }
    }

    public func reset() throws {
        try dbQueue.write { db in
            try InboxRecord.deleteAll(db)
        }
    }

    public func mergeRemote(_ remote: [InboxItem]) throws {
        try dbQueue.write { db in
            for item in remote {
                try InboxRecord(item: item).save(db)
            }
        }
    }

    private static func createSchema(_ db: Database) throws {
        try db.create(table: InboxRecord.databaseTableName, ifNotExists: true) { table in
            table.column("id", .text).primaryKey()
            table.column("user_id", .text).notNull()
            table.column("status", .text).notNull()
            table.column("created_at", .double).notNull()
            table.column("is_processed", .boolean).notNull().defaults(to: false)
            table.column("payload", .blob).notNull()
        }
        try db.create(index: "idx_inbox_user_id", on: InboxRecord.databaseTableName, columns: ["user_id"], ifNotExists: true)
        try db.create(index: "idx_inbox_created_at", on: InboxRecord.databaseTableName, columns: ["created_at"], ifNotExists: true)
        try db.create(index: "idx_inbox_status", on: InboxRecord.databaseTableName, columns: ["status"], ifNotExists: true)
    }

    static func encode(_ item: InboxItem) throws -> Data {
        try jsonEncoder.encode(item)
    }

    static func decode(_ data: Data) throws -> InboxItem {
        try jsonDecoder.decode(InboxItem.self, from: data)
    }
}

private struct InboxRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "inbox_items"

    var id: String
    var userId: String
    var status: String
    var createdAt: Double
    var isProcessed: Bool
    var payload: Data

    enum Columns: String, ColumnExpression {
        case id
        case userId = "user_id"
        case status
        case createdAt = "created_at"
        case isProcessed = "is_processed"
        case payload
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case status
        case createdAt = "created_at"
        case isProcessed = "is_processed"
        case payload
    }

    init(item: InboxItem) throws {
        id = item.id
        userId = item.userId
        status = item.status.rawValue
        createdAt = item.createdAt.timeIntervalSince1970
        isProcessed = item.status != .unprocessed
        payload = try InboxSQLiteStore.encode(item)
    }

    func inboxItem() throws -> InboxItem {
        try InboxSQLiteStore.decode(payload)
    }
}
