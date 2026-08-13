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
        let fetched = try? await healthRepo.getLatest(for: userId)
        latest = Self.preferred(existing: latest, incoming: fetched)
        return latest
    }

    public func applySaved(_ summary: HealthSummary?) {
        latest = Self.preferred(existing: latest, incoming: summary)
    }

    public func reset() {
        latest = nil
    }

    /// Never replace a rich in-memory summary with nil / weaker fetch results.
    private static func preferred(existing: HealthSummary?, incoming: HealthSummary?) -> HealthSummary? {
        switch (existing, incoming) {
        case (nil, nil):
            return nil
        case (let existing?, nil):
            return existing
        case (nil, let incoming?):
            return incoming
        case (let existing?, let incoming?):
            let existingScore = signalScore(existing)
            let incomingScore = signalScore(incoming)
            if incomingScore != existingScore {
                return incomingScore > existingScore ? incoming : existing
            }
            return incoming.date >= existing.date ? incoming : existing
        }
    }

    private static func signalScore(_ summary: HealthSummary) -> Int {
        var score = 0
        if (summary.totalSleepMinutes ?? 0) > 0 { score += 4 }
        if (summary.stepCount ?? 0) > 0 { score += 2 }
        if summary.restingHeartRate != nil || summary.averageHeartRate != nil { score += 2 }
        if summary.hrvAverage != nil { score += 1 }
        if (summary.workoutCount ?? 0) > 0 { score += 1 }
        return score
    }
}
