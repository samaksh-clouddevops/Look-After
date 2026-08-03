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

        return GLMUsageSummary(
            dailyRequestCount: daily.count,
            monthlyRequestCount: monthly.count,
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

    /// GLM 5.2 approximate pricing for developer tracking.
    public static func estimateCostUSD(promptTokens: Int, completionTokens: Int) -> Double {
        let inputRate = 0.0000014
        let outputRate = 0.0000044
        return Double(promptTokens) * inputRate + Double(completionTokens) * outputRate
    }

    private func loadLocked() -> [GLMUsageRecord] {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([GLMUsageRecord].self, from: data)
        else { return [] }
        return decoded
    }

    private func persistLocked(_ records: [GLMUsageRecord]) {
        if let data = try? JSONEncoder().encode(records) {
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
