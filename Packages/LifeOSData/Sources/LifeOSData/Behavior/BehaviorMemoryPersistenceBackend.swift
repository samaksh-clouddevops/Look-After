import Foundation
import LifeOSCore

/// File-based persistence backend for Behavior Memory.
///
/// Uses atomic writes (temp file + replace) under Application Support.
/// Replaceable by CloudKit or other backends conforming to `BehaviorMemoryPersistenceBackendProtocol`.
public final class FileBehaviorMemoryPersistenceBackend: BehaviorMemoryPersistenceBackendProtocol, @unchecked Sendable {

    public static let defaultFileName = "behavior_memory.json"

    private let fileManager: FileManager
    private let directoryURL: URL
    private let fileURL: URL
    private let quarantineDirectoryURL: URL
    private let ioQueue = DispatchQueue(label: "com.flowos.behavior-memory.file-io", qos: .utility)

    /// Production initializer using Application Support/BehaviorMemory.
    public convenience init(
        fileManager: FileManager = .default,
        fileName: String = FileBehaviorMemoryPersistenceBackend.defaultFileName
    ) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = base.appendingPathComponent("BehaviorMemory", isDirectory: true)
        self.init(directoryURL: directory, fileName: fileName, fileManager: fileManager)
    }

    /// Designated initializer — inject `directoryURL` in tests for isolation.
    public init(
        directoryURL: URL,
        fileName: String = FileBehaviorMemoryPersistenceBackend.defaultFileName,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL
        self.fileURL = directoryURL.appendingPathComponent(fileName)
        self.quarantineDirectoryURL = directoryURL.appendingPathComponent("Quarantine", isDirectory: true)
        ensureDirectoriesExist()
    }

    public func loadData() async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async { [self] in
                do {
                    guard fileManager.fileExists(atPath: fileURL.path) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let data = try Data(contentsOf: fileURL)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func saveData(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ioQueue.async { [self] in
                do {
                    ensureDirectoriesExist()
                    let tempURL = fileURL.appendingPathExtension("tmp")
                    try data.write(to: tempURL, options: .atomic)
                    if fileManager.fileExists(atPath: fileURL.path) {
                        try fileManager.removeItem(at: fileURL)
                    }
                    try fileManager.moveItem(at: tempURL, to: fileURL)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Moves corrupt bytes into Quarantine for diagnostics without blocking recovery.
    func quarantineCorruptData(_ data: Data, fileName: String) {
        ioQueue.sync { [self] in
            ensureDirectoriesExist()
            let url = quarantineDirectoryURL.appendingPathComponent(fileName)
            try? data.write(to: url, options: .atomic)
        }
    }

    private func ensureDirectoriesExist() {
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: quarantineDirectoryURL, withIntermediateDirectories: true)
    }
}

/// In-memory backend for unit tests and previews.
public final class InMemoryBehaviorMemoryPersistenceBackend: BehaviorMemoryPersistenceBackendProtocol, @unchecked Sendable {

    private var storedData: Data?
    private let queue = DispatchQueue(label: "com.flowos.behavior-memory.memory-io")

    public init(initialData: Data? = nil) {
        storedData = initialData
    }

    public func loadData() async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: storedData)
            }
        }
    }

    public func saveData(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                storedData = data
                continuation.resume()
            }
        }
    }
}
