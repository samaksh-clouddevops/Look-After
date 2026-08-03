import Foundation

/// Runs an async operation with a maximum duration; cancels the loser when one finishes.
enum AsyncTimeout {
    struct TimeoutError: Error, LocalizedError {
        var errorDescription: String? { "Operation timed out." }
    }

    static func withTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            defer { group.cancelAll() }
            guard let value = try await group.next() else {
                throw TimeoutError()
            }
            return value
        }
    }
}
