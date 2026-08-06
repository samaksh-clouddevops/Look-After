import Foundation
import LookAfterCore
import LookAfterData

/// App-facing batch synthesizer. Pure math lives in `LookAfterCore.TelemetrySynthesizer`.
@MainActor
public final class TelemetrySynthesizerService {
    public static let shared = TelemetrySynthesizerService()

    private let vaultStore: BehavioralVaultStore
    private let log: InteractionTelemetryLogger

    public init(
        vaultStore: BehavioralVaultStore = BehavioralVaultStore(),
        log: InteractionTelemetryLogger = .shared
    ) {
        self.vaultStore = vaultStore
        self.log = log
    }

    /// Ingest all sealed telemetry day-files into the vault (time-agnostic).
    @discardableResult
    public func synthesizeDailyTelemetry(
        activeScheduleHashes: Set<String> = [],
        now: Date = Date(),
        config: TelemetrySynthesizerConfig = .default
    ) async -> TelemetrySynthesisResult {
        await vaultStore.synthesize(
            logger: log,
            activeScheduleHashes: activeScheduleHashes,
            now: now,
            config: config
        )
    }

    public func learnedConstraint(for task: LifeTask) async -> TimeConstraint? {
        let hash = BehavioralSemanticHash.make(for: task)
        return await vaultStore.signature(for: hash)?.learnedConstraint
    }

    public func resetSignature(for hash: String) async -> Bool {
        await vaultStore.resetSignature(for: hash)
    }

    public func resetSignature(for task: LifeTask) async -> Bool {
        await resetSignature(for: BehavioralSemanticHash.make(for: task))
    }

    /// Starvation protocol: if vault is stale >48h, catch up on a utility queue.
    public func catchUpIfStarved(
        activeScheduleHashes: Set<String> = [],
        now: Date = Date()
    ) {
        Task.detached(priority: .utility) { [vaultStore, log] in
            let starved = await vaultStore.isStarved(now: now)
            guard starved else { return }
            _ = await vaultStore.synthesize(
                logger: log,
                activeScheduleHashes: activeScheduleHashes,
                now: now
            )
        }
    }

    /// Onboarding Day-1 intelligence from 6 months of calendar history (mathematical profile only).
    @discardableResult
    public func seedFromCalendarHistory(
        events: [CalendarHistoryEvent],
        now: Date = Date()
    ) async -> (seeded: Bool, profile: RhythmProfile) {
        await vaultStore.seedFromCalendarHistory(events: events, now: now)
    }

    @discardableResult
    public func seedFromRhythmProfile(_ profile: RhythmProfile, now: Date = Date()) async -> Bool {
        await vaultStore.seedFromRhythmProfile(profile, now: now)
    }
}
