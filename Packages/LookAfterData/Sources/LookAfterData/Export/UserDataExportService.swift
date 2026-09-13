import Foundation
import LookAfterCore
import CryptoKit

/// Builds a portable JSON export of local user data (Phase 8.2).
///
/// Output is a single JSON object; optional passphrase wraps AES-GCM ciphertext.
public enum UserDataExportService {

    public struct ExportBundle: Codable, Sendable {
        public var version: Int
        public var exportedAt: Date
        public var userId: String
        public var tasks: [LifeTask]
        public var inbox: [InboxItem]
        public var healthSummaries: [HealthSummary]
        public var bills: [BillItem]
        public var shopping: [ShoppingItem]
        public var relationships: [RelationshipContact]
        public var journal: [JournalEntry]
    }

    public enum ExportError: Error, LocalizedError {
        case encodeFailed
        case encryptFailed

        public var errorDescription: String? {
            switch self {
            case .encodeFailed: return "Could not encode export"
            case .encryptFailed: return "Could not encrypt export"
            }
        }
    }

    /// Gather local snapshots for the user (no network).
    @MainActor
    public static func buildBundle(userId: String) throws -> ExportBundle {
        let tasks = TaskStore.shared.localAllTasks(for: userId)
        let inbox = (try? InboxSQLiteStore.shared.loadAll(userId: userId)) ?? []
        let health = ((try? HealthSummarySQLiteStore.shared.loadAll()) ?? [])
            .filter { $0.userId == userId || $0.userId.isEmpty }
        let bills = ModuleLocalStore.loadBills().filter { $0.userId == userId || $0.userId.isEmpty }
        let shopping = ModuleLocalStore.loadShopping().filter { $0.userId == userId || $0.userId.isEmpty }
        let relationships = ModuleLocalStore.loadRelationships().filter { $0.userId == userId || $0.userId.isEmpty }
        let journal = ModuleLocalStore.loadJournal().filter { $0.userId == userId || $0.userId.isEmpty }

        return ExportBundle(
            version: 1,
            exportedAt: Date(),
            userId: userId,
            tasks: tasks,
            inbox: inbox,
            healthSummaries: health,
            bills: bills,
            shopping: shopping,
            relationships: relationships,
            journal: journal
        )
    }

    public static func exportJSON(userId: String) async throws -> Data {
        let bundle = try await MainActor.run { try buildBundle(userId: userId) }
        return try SharedFormatters.jsonEncoderSeconds.encode(bundle)
    }

    /// AES-GCM with key derived from passphrase via SHA256 (simple local backup).
    public static func exportEncrypted(userId: String, passphrase: String) async throws -> Data {
        let plain = try await exportJSON(userId: userId)
        let digest = SHA256.hash(data: Data(passphrase.utf8))
        let key = SymmetricKey(data: Data(digest))
        guard let sealed = try? AES.GCM.seal(plain, using: key),
              let combined = sealed.combined else {
            throw ExportError.encryptFailed
        }
        return combined
    }

    /// Writes clear JSON under the user storage root and returns the file URL.
    public static func writeExportFile(userId: String) async throws -> URL {
        let data = try await exportJSON(userId: userId)
        let name = "lookafter-export-\(Int(Date().timeIntervalSince1970)).json"
        let url = UserStorageRoot.fileURL(userId: userId, name: name)
        try data.write(to: url, options: .atomic)
        return url
    }
}
