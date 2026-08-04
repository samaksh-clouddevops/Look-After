import Foundation
import os.signpost

/// Lightweight performance instrumentation for main-thread and critical-path work.
/// Logs slow operations in DEBUG and emits os_signpost intervals for Instruments.
public enum PerformanceMonitor {
    private static let log = OSLog(subsystem: "com.samaksh.flowos", category: "Performance")
    private static let signposter = OSSignposter(logHandle: log)

    /// Default frame budget in milliseconds (60fps).
    public static let frameBudgetMs: Double = 16

    /// Measure a synchronous block. Logs when duration exceeds `warnAfterMs`.
    @discardableResult
    public static func measure<T>(
        _ label: String,
        warnAfterMs: Double = frameBudgetMs,
        _ block: () throws -> T
    ) rethrows -> T {
        let state = signposter.beginInterval(label, id: signposter.makeSignpostID())
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let durationMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            signposter.endInterval(label, state)
            #if DEBUG
            if durationMs > warnAfterMs {
                print(String(format: "⚠️ [PERF] %@: %.1fms (budget %.0fms)", label, durationMs, warnAfterMs))
            }
            #endif
        }
        return try block()
    }

    /// Measure an async block. Logs when duration exceeds `warnAfterMs`.
    @discardableResult
    public static func measureAsync<T>(
        _ label: String,
        warnAfterMs: Double = 100,
        _ block: () async throws -> T
    ) async rethrows -> T {
        let state = signposter.beginInterval(label, id: signposter.makeSignpostID())
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let durationMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            signposter.endInterval(label, state)
            #if DEBUG
            if durationMs > warnAfterMs {
                print(String(format: "⚠️ [PERF] %@: %.1fms (budget %.0fms)", label, durationMs, warnAfterMs))
            }
            #endif
        }
        return try await block()
    }
}
