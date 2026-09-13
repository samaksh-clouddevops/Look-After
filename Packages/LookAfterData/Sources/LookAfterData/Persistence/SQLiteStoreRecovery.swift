import Foundation
import GRDB

/// Shared recovery logic for local SQLite store bootstrap.
///
/// If opening/preparing the database fails (e.g. a corrupted or truncated
/// file from an interrupted write), the offending file is quarantined
/// (renamed aside, along with any `-wal`/`-shm` sidecars) and a fresh
/// database is created in its place, rather than crashing the app on
/// every subsequent launch.
enum SQLiteStoreRecovery {

    /// Opens a `DatabaseQueue` at `databaseURL` and runs `prepare` (schema
    /// creation, etc.) against it. On failure, quarantines the existing
    /// file (if any) and retries once with a fresh database. Only throws
    /// if the retry after quarantine also fails.
    static func openWithQuarantineFallback(
        databaseURL: URL,
        configuration: Configuration,
        storeName: String,
        prepare: (Database) throws -> Void
    ) throws -> DatabaseQueue {
        func attempt() throws -> DatabaseQueue {
            let queue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
            try queue.write(prepare)
            return queue
        }

        do {
            return try attempt()
        } catch {
            print("[\(storeName)] Failed to open database at \(databaseURL.path): \(error). Quarantining and recreating.")
            quarantineFile(at: databaseURL, storeName: storeName)
            // Retry once with a clean slate. If this also fails (e.g. disk
            // full, sandbox permissions), propagate — nothing more can be
            // done locally.
            return try attempt()
        }
    }

    /// Renames the database file (and WAL/SHM sidecars, if present) aside
    /// so a fresh database can be created at the original path. Best-effort;
    /// failures to quarantine are logged but do not block the retry.
    private static func quarantineFile(at databaseURL: URL, storeName: String) {
        guard databaseURL.path != ":memory:" else { return }
        let fm = FileManager.default
        let suffix = Int(Date().timeIntervalSince1970)
        for candidate in [databaseURL.path, databaseURL.path + "-wal", databaseURL.path + "-shm"] {
            guard fm.fileExists(atPath: candidate) else { continue }
            let quarantinePath = candidate + ".corrupt.\(suffix)"
            do {
                try fm.removeItem(atPath: quarantinePath)
            } catch {
                // No pre-existing quarantine file to remove — ignore.
            }
            do {
                try fm.moveItem(atPath: candidate, toPath: quarantinePath)
            } catch {
                print("[\(storeName)] Failed to quarantine \(candidate): \(error)")
                // Best effort — if we can't even move it aside, delete it so
                // the retry has a chance of succeeding.
                try? fm.removeItem(atPath: candidate)
            }
        }
    }
}
