import Foundation
import LookAfterCore

/// Manages on-device JSON persistence for all LifeOS modules as a fallback when Firebase is offline or unauthenticated.
public final class LocalPersistenceManager {
    
    public static let shared = LocalPersistenceManager()
    private let fileManager = FileManager.default
    
    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private init() {}
    
    /// Save an array of Codable items to a local JSON file.
    public func save<T: Encodable>(_ items: [T], filename: String) {
        let url = documentsDirectory.appendingPathComponent("\(filename).json")
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let data = try encoder.encode(items)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[LocalPersistenceManager] Error saving \(filename): \(error)")
        }
    }
    
    /// Load an array of Codable items from a local JSON file.
    public func load<T: Decodable>(_ type: [T].Type, filename: String) -> [T] {
        let url = documentsDirectory.appendingPathComponent("\(filename).json")
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        
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

    /// Delete a single persisted JSON file.
    public func deleteFile(named filename: String) {
        let url = documentsDirectory.appendingPathComponent("\(filename).json")
        guard fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.removeItem(at: url)
    }

    /// Remove every JSON file in the documents directory (developer reset).
    public func deleteAllJSONFiles() {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: documentsDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        for url in urls where url.pathExtension == "json" {
            try? fileManager.removeItem(at: url)
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
