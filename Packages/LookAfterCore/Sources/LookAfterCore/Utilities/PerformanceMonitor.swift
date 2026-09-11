import Foundation
import os

/// Lightweight performance instrumentation for main-thread and critical-path work.
/// Logs slow operations in DEBUG and emits os_signpost intervals for Instruments.
public enum PerformanceMonitor {
    private static let log = OSLog(subsystem: "com.samaksh.flowos", category: "Performance")

    /// Default frame budget in milliseconds (60fps).
    public static let frameBudgetMs: Double = 16

    /// Measure a synchronous block. Logs when duration exceeds `warnAfterMs`.
    @discardableResult
    public static func measure<T>(
        _ label: String,
        warnAfterMs: Double = frameBudgetMs,
        _ block: () throws -> T
    ) rethrows -> T {
        let signpostID = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "Measure", signpostID: signpostID, "%{public}s", label)
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let durationMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            os_signpost(.end, log: log, name: "Measure", signpostID: signpostID, "%{public}s", label)
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
        isolation: isolated (any Actor)? = #isolation,
        _ block: () async throws -> T
    ) async rethrows -> T {
        _ = isolation
        let signpostID = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "MeasureAsync", signpostID: signpostID, "%{public}s", label)
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let durationMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            os_signpost(.end, log: log, name: "MeasureAsync", signpostID: signpostID, "%{public}s", label)
            #if DEBUG
            if durationMs > warnAfterMs {
                print(String(format: "⚠️ [PERF] %@: %.1fms (budget %.0fms)", label, durationMs, warnAfterMs))
            }
            #endif
        }
        return try await block()
    }

    /// Named os_signpost interval for QA-09 benchmarks (matches `PerformanceSignposts` names in the app target).
    @discardableResult
    public static func signpostInterval<T>(
        _ name: StaticString,
        warnAfterMs: Double = frameBudgetMs,
        _ block: () throws -> T
    ) rethrows -> T {
        let signpostID = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: signpostID)
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let durationMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            os_signpost(.end, log: log, name: name, signpostID: signpostID)
            #if DEBUG
            if durationMs > warnAfterMs {
                print(String(format: "⚠️ [PERF] %@: %.1fms (budget %.0fms)", "\(name)", durationMs, warnAfterMs))
            }
            #endif
        }
        return try block()
    }
}
