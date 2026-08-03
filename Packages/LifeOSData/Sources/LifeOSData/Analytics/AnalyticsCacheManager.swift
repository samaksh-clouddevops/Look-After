import Foundation
import LifeOSCore

/// Disk + memory cache for precomputed analytics. UI reads here first.
public final class AnalyticsCacheManager: @unchecked Sendable {

    public static let shared = AnalyticsCacheManager()

    private let local = LocalPersistenceManager.shared
    private let lock = NSLock()
    private var memoryBundles: [String: AnalyticsCacheBundle] = [:]

    private init() {}

    // MARK: - Read (fast path)

    public func cachedReport(timeframe: InsightsTimeframe, userId: String) -> PersonalAnalyticsReport? {
        lock.lock()
        defer { lock.unlock() }
        if let memory = memoryBundles[userId]?.reports[timeframe.rawValue] {
            return memory
        }
        return loadBundle(userId: userId)?.reports[timeframe.rawValue]
    }

    public func cachedAIContext(userId: String) -> CachedAIContextSummary? {
        lock.lock()
        defer { lock.unlock() }
        if let memory = memoryBundles[userId]?.aiContext {
            return memory
        }
        return loadBundle(userId: userId)?.aiContext
    }

    public func cachedSnapshots(userId: String) -> [AnalyticsDailySnapshot] {
        lock.lock()
        defer { lock.unlock() }
        if let memory = memoryBundles[userId]?.snapshots {
            return memory
        }
        return loadBundle(userId: userId)?.snapshots ?? []
    }

    public func cacheState(userId: String) -> AnalyticsCacheState? {
        lock.lock()
        defer { lock.unlock() }
        if let memory = memoryBundles[userId]?.state {
            return memory
        }
        return loadBundle(userId: userId)?.state
    }

    public func lastRefreshDate(userId: String) -> Date? {
        cacheState(userId: userId)?.lastRefreshAt
    }

    // MARK: - Write

    public func saveBundle(_ bundle: AnalyticsCacheBundle, userId: String) {
        lock.lock()
        memoryBundles[userId] = bundle
        lock.unlock()

        local.save([bundle], filename: filename(for: userId))
    }

    public func saveReports(_ reports: [InsightsTimeframe: PersonalAnalyticsReport], userId: String) {
        var bundle = loadBundle(userId: userId) ?? AnalyticsCacheBundle(state: AnalyticsCacheState(userId: userId))
        for (timeframe, report) in reports {
            bundle.reports[timeframe.rawValue] = report
        }
        saveBundle(bundle, userId: userId)
    }

    public func saveSnapshots(_ snapshots: [AnalyticsDailySnapshot], state: AnalyticsCacheState, userId: String) {
        var bundle = loadBundle(userId: userId) ?? AnalyticsCacheBundle(state: AnalyticsCacheState(userId: userId))
        bundle.snapshots = snapshots
        bundle.state = state
        saveBundle(bundle, userId: userId)
    }

    public func saveAIContext(_ context: CachedAIContextSummary, userId: String) {
        var bundle = loadBundle(userId: userId) ?? AnalyticsCacheBundle(state: AnalyticsCacheState(userId: userId))
        bundle.aiContext = context
        saveBundle(bundle, userId: userId)
    }

    public func invalidate(userId: String) {
        lock.lock()
        memoryBundles.removeValue(forKey: userId)
        lock.unlock()
        local.deleteFile(named: analyticsFilename(for: userId))
    }

    public func invalidateAll() {
        lock.lock()
        memoryBundles.removeAll()
        lock.unlock()
        local.deleteFiles(withNamePrefix: "analytics_cache_")
    }

    private func analyticsFilename(for userId: String) -> String {
        let sanitized = userId.isEmpty ? "default" : userId.replacingOccurrences(of: "/", with: "_")
        return "analytics_cache_\(sanitized)"
    }

    public func markStale(userId: String) {
        guard var bundle = loadBundle(userId: userId) else { return }
        if var context = bundle.aiContext {
            context.isStale = true
            bundle.aiContext = context
        }
        saveBundle(bundle, userId: userId)
    }

    // MARK: - Private

    private func filename(for userId: String) -> String {
        "analytics_cache_\(sanitized(userId))"
    }

    private func sanitized(_ userId: String) -> String {
        userId.isEmpty ? "default" : userId.replacingOccurrences(of: "/", with: "_")
    }

    private func loadBundle(userId: String) -> AnalyticsCacheBundle? {
        let bundles = local.load([AnalyticsCacheBundle].self, filename: filename(for: userId))
        return bundles.first
    }
}
