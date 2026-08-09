import Foundation
import LookAfterCore

/// Tracks GLM API usage for Developer Settings.
public final class GLMUsageLogger: @unchecked Sendable {
    public static let shared = GLMUsageLogger()

    private let storageKey = "glmUsageRecords"
    private let lock = NSLock()
    private let maxStoredRecords = 500

    private init() {}

    public func log(_ record: GLMUsageRecord) {
        lock.lock()
        defer { lock.unlock() }
        var records = loadLocked()
        records.insert(record, at: 0)
        if records.count > maxStoredRecords {
            records = Array(records.prefix(maxStoredRecords))
        }
        persistLocked(records)
    }

    public func summary() -> GLMUsageSummary {
        lock.lock()
        defer { lock.unlock() }
        let records = loadLocked()
        let calendar = Calendar.current
        let now = Date()
        let dayStart = calendar.startOfDay(for: now)
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? dayStart

        let daily = records.filter { $0.timestamp >= dayStart }
        let monthly = records.filter { $0.timestamp >= monthStart }

        let dailyPrompt = daily.reduce(0) { $0 + $1.promptTokens }
        let dailyCompletion = daily.reduce(0) { $0 + $1.completionTokens }
        let monthlyPrompt = monthly.reduce(0) { $0 + $1.promptTokens }
        let monthlyCompletion = monthly.reduce(0) { $0 + $1.completionTokens }

        return GLMUsageSummary(
            dailyRequestCount: daily.count,
            monthlyRequestCount: monthly.count,
            dailyPromptTokens: dailyPrompt,
            dailyCompletionTokens: dailyCompletion,
            dailyTotalTokens: dailyPrompt + dailyCompletion,
            monthlyPromptTokens: monthlyPrompt,
            monthlyCompletionTokens: monthlyCompletion,
            monthlyTotalTokens: monthlyPrompt + monthlyCompletion,
            dailyTotalUSD: daily.reduce(0) { $0 + $1.estimatedCostUSD },
            monthlyTotalUSD: monthly.reduce(0) { $0 + $1.estimatedCostUSD },
            recentRecords: Array(records.prefix(50))
        )
    }

    public func clear() {
        lock.lock()
        persistLocked([])
        lock.unlock()
    }

    /// GLM approximate pricing for developer tracking (varies by model tier).
    public static func estimateCostUSD(model: String, promptTokens: Int, completionTokens: Int) -> Double {
        let rates = ratesForModel(model)
        return Double(promptTokens) * rates.input + Double(completionTokens) * rates.output
    }

    public static func estimateCostUSD(promptTokens: Int, completionTokens: Int) -> Double {
        estimateCostUSD(model: GLMConfiguration.defaultModel, promptTokens: promptTokens, completionTokens: completionTokens)
    }

    /// Per-token USD rates derived from https://docs.z.ai/guides/overview/pricing (per 1M tokens).
    private static func ratesForModel(_ model: String) -> (input: Double, output: Double) {
        let normalized = model.lowercased()

        // FlashX is paid — check before generic "flash".
        if normalized.contains("flashx") {
            if normalized.contains("4.6v") {
                return (0.00000004, 0.0000004) // GLM-4.6V-FlashX: $0.04 / $0.40 per 1M
            }
            return (0.00000007, 0.0000004) // GLM-4.7-FlashX: $0.07 / $0.40 per 1M
        }

        // GLM-4.7-Flash, GLM-4.5-Flash, GLM-4.6V-Flash are free on z.ai.
        if normalized.contains("flash") {
            return (0, 0)
        }

        if normalized.contains("airx") {
            return (0.0000011, 0.0000045) // GLM-4.5-AirX
        }
        if normalized.contains("air") {
            return (0.0000002, 0.0000011) // GLM-4.5-Air
        }
        if normalized.contains("32b") {
            return (0.0000001, 0.0000001) // GLM-4-32B
        }
        if normalized.contains("4.7") || normalized.contains("4.6") || normalized.contains("4.5") {
            return (0.0000006, 0.0000022) // GLM-4.7 / 4.6 / 4.5
        }
        if normalized.contains("5-turbo") || normalized.contains("5.1") || normalized.contains("5.2") {
            return (0.0000014, 0.0000044) // GLM-5.1 / 5.2 / 5-Turbo
        }
        if normalized.contains("glm-5") {
            return (0.000001, 0.0000032) // GLM-5 base
        }
        return (0.0000014, 0.0000044)
    }

    private func loadLocked() -> [GLMUsageRecord] {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let decoded = try? SharedFormatters.jsonDecoderSeconds.decode([GLMUsageRecord].self, from: data)
        else { return [] }
        return decoded
    }

    private func persistLocked(_ records: [GLMUsageRecord]) {
        if let data = try? SharedFormatters.jsonEncoderSeconds.encode(records) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

#if DEBUG
extension GLMUsageLogger {
    func replaceRecordsForTesting(_ records: [GLMUsageRecord]) {
        lock.lock()
        persistLocked(records)
        lock.unlock()
    }
}
#endif
