import Foundation
import GRDB
import LookAfterCore

/// On-device SQLite for module entities (bills, shopping, relationships, journal) — H4.
public final class ModuleEntitySQLiteStore: @unchecked Sendable {
    public static let shared = ModuleEntitySQLiteStore()

    public enum Collection: String, CaseIterable, Sendable {
        case bills
        case shoppingItems = "shopping_items"
        case relationships
        case journalEntries = "journal_entries"
    }

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
        self.init(databaseURL: documents.appendingPathComponent("modules.sqlite"), documentsDirectory: documents)
    }

    public convenience init(inMemory: Bool) {
        if inMemory {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("modules-\(UUID().uuidString).sqlite")
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
            fatalError("[ModuleEntitySQLiteStore] Failed to open database: \(error)")
        }
    }

    public func loadAll<T: Decodable>(_ type: T.Type, collection: Collection) throws -> [T] {
        try dbQueue.read { db in
            let records = try ModuleEntityRecord
                .filter(ModuleEntityRecord.Columns.collection == collection.rawValue)
                .fetchAll(db)
            return try records.map { try Self.decode(T.self, from: $0.payload) }
        }
    }

    public func replaceAll<T: Encodable>(_ items: [T], collection: Collection, id: (T) -> String) throws {
        try dbQueue.write { db in
            try ModuleEntityRecord
                .filter(ModuleEntityRecord.Columns.collection == collection.rawValue)
                .deleteAll(db)
            for item in items {
                let record = try ModuleEntityRecord(
                    collection: collection.rawValue,
                    id: id(item),
                    payload: Self.encode(item)
                )
                try record.save(db)
            }
        }
    }

    public func upsert<T: Encodable>(_ item: T, collection: Collection, id: String) throws {
        try dbQueue.write { db in
            let record = try ModuleEntityRecord(
                collection: collection.rawValue,
                id: id,
                payload: Self.encode(item)
            )
            try record.save(db)
        }
    }

    public func delete(collection: Collection, id: String) throws {
        try dbQueue.write { db in
            _ = try ModuleEntityRecord.deleteOne(db, key: ["collection": collection.rawValue, "id": id])
        }
    }

    public func reset() throws {
        _ = try dbQueue.write { db in
            try ModuleEntityRecord.deleteAll(db)
        }
    }

    private static func createSchema(_ db: Database) throws {
        try db.create(table: ModuleEntityRecord.databaseTableName, ifNotExists: true) { table in
            table.column("collection", .text).notNull()
            table.column("id", .text).notNull()
            table.column("payload", .blob).notNull()
            table.primaryKey(["collection", "id"])
        }
        try db.create(
            index: "idx_module_entities_collection",
            on: ModuleEntityRecord.databaseTableName,
            columns: ["collection"],
            ifNotExists: true
        )
    }

    private static func migrateFromJSONIfNeeded(_ db: Database, documentsDirectory: URL) throws {
        let flagURL = documentsDirectory.appendingPathComponent("modules_sqlite_migrated.flag")
        guard !FileManager.default.fileExists(atPath: flagURL.path) else { return }

        let persistence = LocalPersistenceManager.shared
        for collection in Collection.allCases {
            let existing = try ModuleEntityRecord
                .filter(ModuleEntityRecord.Columns.collection == collection.rawValue)
                .fetchCount(db)
            guard existing == 0 else { continue }

            let rawItems: [(id: String, data: Data)]
            switch collection {
            case .bills:
                let items: [BillItem] = persistence.load([BillItem].self, filename: collection.rawValue)
                rawItems = items.compactMap { item in
                    guard let data = try? encode(item) else { return nil }
                    return (item.id, data)
                }
            case .shoppingItems:
                let items: [ShoppingItem] = persistence.load([ShoppingItem].self, filename: collection.rawValue)
                rawItems = items.compactMap { item in
                    guard let data = try? encode(item) else { return nil }
                    return (item.id, data)
                }
            case .relationships:
                let items: [RelationshipContact] = persistence.load([RelationshipContact].self, filename: collection.rawValue)
                rawItems = items.compactMap { item in
                    guard let data = try? encode(item) else { return nil }
                    return (item.id, data)
                }
            case .journalEntries:
                let items: [JournalEntry] = persistence.load([JournalEntry].self, filename: collection.rawValue)
                rawItems = items.compactMap { item in
                    guard let data = try? encode(item) else { return nil }
                    return (item.id, data)
                }
            }

            for item in rawItems {
                try ModuleEntityRecord(collection: collection.rawValue, id: item.id, payload: item.data).save(db)
            }
        }

        try? Data().write(to: flagURL)
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        try jsonEncoder.encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try jsonDecoder.decode(type, from: data)
    }
}

private struct ModuleEntityRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "module_entities"

    var collection: String
    var id: String
    var payload: Data

    enum Columns: String, ColumnExpression {
        case collection
        case id
        case payload
    }

    enum CodingKeys: String, CodingKey {
        case collection
        case id
        case payload
    }

    init(collection: String, id: String, payload: Data) {
        self.collection = collection
        self.id = id
        self.payload = payload
    }
}
