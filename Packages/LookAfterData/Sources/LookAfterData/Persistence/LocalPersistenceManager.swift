import Foundation
import LookAfterCore

/// Manages on-device JSON persistence for all LifeOS modules as a fallback when Firebase is offline or unauthenticated.
/// Performance optimized: Encode + disk write happen on a serial background queue so the main thread stays free.
/// Loads use a barrier so they never race with pending writes for the same file.
public final class LocalPersistenceManager: @unchecked Sendable {

    public static let shared = LocalPersistenceManager()
    private let fileManager = FileManager.default
    /// Serial queue — all save/load/delete serialized to prevent race conditions.
    private let ioQueue = DispatchQueue(label: "com.lookafter.persistence", qos: .userInitiated)

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private init() {}

    /// Save an array of Codable items to a local JSON file.
    /// Encoding and disk I/O run off the main thread. Call returns immediately.
    public func save<T: Encodable>(_ items: [T], filename: String) {
        // Capture encoded data off-main when possible: schedule whole op on ioQueue.
        let url = documentsDirectory.appendingPathComponent("\(filename).json")
        ioQueue.async {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .secondsSince1970
                let data = try encoder.encode(items)
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                try? FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: url.path
                )
            } catch {
                print("[LocalPersistenceManager] Error saving \(filename): \(error)")
            }
        }
    }

    /// Save an array of Codable items and wait until the write completes.
    public func saveAsync<T: Encodable>(_ items: [T], filename: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let url = documentsDirectory.appendingPathComponent("\(filename).json")
            ioQueue.async {
                do {
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .secondsSince1970
                    let data = try encoder.encode(items)
                    try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    try? FileManager.default.setAttributes(
                        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                        ofItemAtPath: url.path
                    )
                } catch {
                    print("[LocalPersistenceManager] Error saving \(filename): \(error)")
                }
                continuation.resume()
            }
        }
    }

    /// Load an array of Codable items from a local JSON file.
    /// Waits for any pending saves (barrier) then reads on the I/O queue so main thread only waits,
    /// never performs encode/decode/disk work itself for multi-KB payloads beyond the sync hop.
    public func load<T: Decodable>(_ type: [T].Type, filename: String) -> [T] {
        let url = documentsDirectory.appendingPathComponent("\(filename).json")
        return ioQueue.sync {
            guard self.fileManager.fileExists(atPath: url.path) else { return [] }
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .secondsSince1970
                return try decoder.decode(type, from: data)
            } catch {
                print("[LocalPersistenceManager] Error loading \(filename): \(error)")
                return []
            }
        }
    }

    /// Load an array of Codable items from a local JSON file without blocking the caller until completion.
    public func loadAsync<T: Decodable>(_ type: [T].Type, filename: String) async -> [T] {
        await withCheckedContinuation { continuation in
            let url = documentsDirectory.appendingPathComponent("\(filename).json")
            ioQueue.async {
                guard self.fileManager.fileExists(atPath: url.path) else {
                    continuation.resume(returning: [])
                    return
                }
                do {
                    let data = try Data(contentsOf: url)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .secondsSince1970
                    let result = try decoder.decode(type, from: data)
                    continuation.resume(returning: result)
                } catch {
                    print("[LocalPersistenceManager] Error loading \(filename): \(error)")
                    continuation.resume(returning: [])
                }
            }
        }
    }

    /// Delete a single persisted JSON file.
    public func deleteFile(named filename: String) {
        let url = documentsDirectory.appendingPathComponent("\(filename).json")
        ioQueue.async {
            guard self.fileManager.fileExists(atPath: url.path) else { return }
            try? self.fileManager.removeItem(at: url)
        }
    }

    /// Remove every JSON file in the documents directory (developer reset).
    public func deleteAllJSONFiles() {
        ioQueue.sync {
            guard let urls = try? self.fileManager.contentsOfDirectory(
                at: self.documentsDirectory,
                includingPropertiesForKeys: nil
            ) else { return }

            for url in urls where url.pathExtension == "json" {
                try? self.fileManager.removeItem(at: url)
            }
        }
    }

    /// Delete Application Support / BehaviorMemory entirely.
    public func deleteBehaviorMemoryDirectory() {
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let dir = base.appendingPathComponent("BehaviorMemory", isDirectory: true)
        try? fileManager.removeItem(at: dir)
    }

    /// Clear app caches (URL cache, temporary directory).
    public func clearApplicationCaches() {
        URLCache.shared.removeAllCachedResponses()
        let tmp = fileManager.temporaryDirectory
        if let tmpContents = try? fileManager.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
            for url in tmpContents {
                try? fileManager.removeItem(at: url)
            }
        }
        if let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first,
           let cacheContents = try? fileManager.contentsOfDirectory(at: caches, includingPropertiesForKeys: nil) {
            for url in cacheContents {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    /// Delete JSON files whose name (without extension) starts with the given prefix.
    public func deleteFiles(withNamePrefix prefix: String) {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: documentsDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        for url in urls {
            let base = url.deletingPathExtension().lastPathComponent
            if base.hasPrefix(prefix) {
                try? fileManager.removeItem(at: url)
            }
        }
    }
}
