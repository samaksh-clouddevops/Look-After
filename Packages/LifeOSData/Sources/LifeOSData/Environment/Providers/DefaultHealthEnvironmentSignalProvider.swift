import Foundation
import LifeOSCore

/// Maps already-fetched `HealthSummary` and `CognitiveSnapshot` into environment signals.
///
/// Does not call HealthKit — health data must be supplied by `HealthSyncService` / app layer.
public struct DefaultHealthEnvironmentSignalProvider: HealthEnvironmentSignalProviderProtocol {

    private let hrvBaselineMs: Double

    public init(hrvBaselineMs: Double = 50) {
        self.hrvBaselineMs = hrvBaselineMs
    }

    public func currentSignals(
        cognitiveSnapshot: CognitiveSnapshot,
        healthSummary: HealthSummary?
    ) async -> HealthEnvironmentSignals {
        guard let health = healthSummary else {
            return HealthEnvironmentSignals(
                energyScore: cognitiveSnapshot.energyScore,
                hrvDelta: 0,
                sleepQuality: .unknown,
                isAvailable: false
            )
        }

        let hrvDelta: Double
        if let hrv = health.hrvAverage, hrvBaselineMs > 0 {
            hrvDelta = (hrv - hrvBaselineMs) / hrvBaselineMs
        } else {
            hrvDelta = 0
        }

        return HealthEnvironmentSignals(
            energyScore: cognitiveSnapshot.energyScore,
            hrvDelta: hrvDelta,
            sleepQuality: mapSleepQuality(from: health),
            isAvailable: true
        )
    }

    private func mapSleepQuality(from health: HealthSummary) -> SleepQuality {
        if let score = health.sleepQualityScore {
            switch score {
            case 0.8...: return .excellent
            case 0.6..<0.8: return .good
            case 0.4..<0.6: return .fair
            default: return .poor
            }
        }
        if let minutes = health.totalSleepMinutes {
            let hours = minutes / 60
            if hours >= 7.5 { return .good }
            if hours >= 6 { return .fair }
            if hours > 0 { return .poor }
        }
        return .unknown
    }
}
