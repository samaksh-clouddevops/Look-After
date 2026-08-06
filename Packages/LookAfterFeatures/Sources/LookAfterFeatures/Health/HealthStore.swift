import Foundation
import LookAfterCore
import LookAfterData

/// Single published source for the latest health summary.
@MainActor
public final class HealthStore: ObservableObject {
    public static let shared = HealthStore()

    @Published public private(set) var latest: HealthSummary?

    private let healthRepo: HealthSummaryRepository

    public init(healthRepo: HealthSummaryRepository? = nil) {
        self.healthRepo = healthRepo ?? HealthSummaryRepository()
    }

    @discardableResult
    public func refresh(userId: String) async -> HealthSummary? {
        guard !userId.isEmpty else { return latest }
        let summary = try? await healthRepo.getLatest(for: userId)
        latest = summary
        return summary
    }

    public func applySaved(_ summary: HealthSummary?) {
        latest = summary
    }

    public func reset() {
        latest = nil
    }
}
