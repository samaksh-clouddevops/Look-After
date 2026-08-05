import Foundation

// MARK: - Config

public struct TelemetrySynthesizerConfig: Sendable, Equatable {
    /// EMA smoothing factor for override intensity (0…1). Higher = more reactive.
    public var emaAlpha: Double
    /// Overrides required before flipping a *high-confidence* baseline.
    public var baselineFlipThreshold: Int
    /// Confidence hit applied to the bucket where the override occurred.
    public var primaryConfidenceDelta: Double
    /// Smaller confidence hit applied to the other two buckets (cross-day bleed).
    public var secondaryConfidenceDelta: Double
    /// Mean confidence at/below this → first contradicting override rewrites baseline provisionally.
    public var immediateCapitulationCeiling: Double
    /// Confidence after a *single* override on a weak signature (provisional — not locked truth).
    /// Kept deliberately mid so an accidental swipe can still be reversed without a 3-strike gauntlet.
    public var provisionalUserConfidence: Double
    /// Confidence after a *confirmed* override (2nd agreeing swipe within confirmation window).
    public var confirmedUserConfidence: Double
    /// active → dormant after this many days of inactivity.
    public var dormancyDays: Int
    /// dormant → delete after this many additional days (total inactivity ≈ dormancy + this).
    public var dormantDeletionDays: Int
    /// Vault age that triggers foreground starvation catch-up.
    public var starvationAge: TimeInterval

    public static let `default` = TelemetrySynthesizerConfig(
        emaAlpha: 0.35,
        baselineFlipThreshold: 3,
        primaryConfidenceDelta: 0.12,
        secondaryConfidenceDelta: 0.03,
        immediateCapitulationCeiling: 0.2,
        provisionalUserConfidence: 0.45,
        confirmedUserConfidence: 0.8,
        dormancyDays: 30,
        dormantDeletionDays: 15,
        starvationAge: 48 * 60 * 60
    )

    public init(
        emaAlpha: Double,
        baselineFlipThreshold: Int,
        primaryConfidenceDelta: Double,
        secondaryConfidenceDelta: Double,
        immediateCapitulationCeiling: Double,
        provisionalUserConfidence: Double,
        confirmedUserConfidence: Double,
        dormancyDays: Int,
        dormantDeletionDays: Int,
        starvationAge: TimeInterval
    ) {
        self.emaAlpha = emaAlpha
        self.baselineFlipThreshold = baselineFlipThreshold
        self.primaryConfidenceDelta = primaryConfidenceDelta
        self.secondaryConfidenceDelta = secondaryConfidenceDelta
        self.immediateCapitulationCeiling = immediateCapitulationCeiling
        self.provisionalUserConfidence = provisionalUserConfidence
        self.confirmedUserConfidence = confirmedUserConfidence
        self.dormancyDays = dormancyDays
        self.dormantDeletionDays = dormantDeletionDays
        self.starvationAge = starvationAge
    }
}

// MARK: - Result

public struct TelemetrySynthesisResult: Sendable, Equatable {
    public var vault: BehavioralVaultEnvelope
    /// Day keys of sealed logs that were fully ingested and may be deleted.
    public var consumedDayKeys: [String]
    public var processedEventCount: Int
    public var updatedHashes: [String]
    public var flippedHashes: [String]
    public var prunedHashes: [String]

    public init(
        vault: BehavioralVaultEnvelope,
        consumedDayKeys: [String],
        processedEventCount: Int,
        updatedHashes: [String],
        flippedHashes: [String],
        prunedHashes: [String] = []
    ) {
        self.vault = vault
        self.consumedDayKeys = consumedDayKeys
        self.processedEventCount = processedEventCount
        self.updatedHashes = updatedHashes
        self.flippedHashes = flippedHashes
        self.prunedHashes = prunedHashes
    }
}

// MARK: - Synthesizer (pure)

/// Batch engine: turns sealed telemetry logs into Behavioral Vault updates.
/// Time-agnostic — ingests *all* provided unprocessed events (2h or 72h old).
public enum TelemetrySynthesizer {

    /// Preferred multi-file entry: sealed day logs only (double-buffer safe).
    public static func synthesizeDailyTelemetry(
        sealedLogs: [(dayKey: String, envelope: TelemetryLogEnvelope)],
        vault: BehavioralVaultEnvelope,
        activeScheduleHashes: Set<String> = [],
        now: Date = Date(),
        config: TelemetrySynthesizerConfig = .default
    ) -> TelemetrySynthesisResult {
        let events = sealedLogs.flatMap(\.envelope.events)
        let dayKeys = sealedLogs.map(\.dayKey)
        return synthesize(
            events: events,
            consumedDayKeys: dayKeys,
            vault: vault,
            activeScheduleHashes: activeScheduleHashes,
            now: now,
            config: config
        )
    }

    /// Convenience for single-buffer / unit tests — processes every event (no 24h filter).
    public static func synthesizeDailyTelemetry(
        log: TelemetryLogEnvelope,
        vault: BehavioralVaultEnvelope,
        activeScheduleHashes: Set<String> = [],
        now: Date = Date(),
        config: TelemetrySynthesizerConfig = .default
    ) -> TelemetrySynthesisResult {
        synthesize(
            events: log.events,
            consumedDayKeys: log.dayKey.isEmpty ? [] : [log.dayKey],
            vault: vault,
            activeScheduleHashes: activeScheduleHashes,
            now: now,
            config: config
        )
    }

    private static func synthesize(
        events: [ConstraintTelemetryEvent],
        consumedDayKeys: [String],
        vault: BehavioralVaultEnvelope,
        activeScheduleHashes: Set<String>,
        now: Date,
        config: TelemetrySynthesizerConfig
    ) -> TelemetrySynthesisResult {
        var nextVault = vault
        var updated: Set<String> = []
        var flipped: Set<String> = []

        let grouped = Dictionary(grouping: events, by: \.semanticHash)

        for (hash, group) in grouped {
            let sorted = group.sorted { $0.timestamp < $1.timestamp }
            var signature = nextVault.signature(for: hash)
                ?? BehavioralSignature.factoryDefault(hash: hash)

            // Resurrection: any telemetry on a dormant hash revives it.
            if case .dormant = signature.state {
                signature.state = .active
            }

            var emaSoftening = 0.0
            var emaHardening = 0.0
            var overrideTicks = 0

            for event in sorted {
                overrideTicks += 1
                signature.overrideCount += 1
                signature.lastSeenInSchedule = max(signature.lastSeenInSchedule ?? event.timestamp, event.timestamp)

                // Sabotage override: user rejected recovery lock → cool-down, don't treat as normal soften.
                if event.source == .sabotageOverride {
                    SabotagePolicyStore.shared.recordSabotageOverride(now: event.timestamp)
                    signature.lastUpdated = event.timestamp
                    continue
                }

                let contradicts =
                    event.newConstraint != signature.learnedConstraint
                    && (event.isSoftening || event.isHardening || event.newConstraint != event.originalConstraint)

                // Weak / seeded baselines (confidence ≤ 0.2): rewrite immediately, but
                // only provisional confidence — a second agreeing swipe confirms to 0.8.
                // Prevents a single accidental fluid-swipe from locking the Brain forever.
                if contradicts, signature.meanConfidence <= config.immediateCapitulationCeiling + 1e-9 {
                    signature.learnedConstraint = event.newConstraint
                    signature.overrideCount = 1
                    signature.isSeededBaseline = false
                    signature.confidence = TemporalConfidence(
                        morning: config.provisionalUserConfidence,
                        afternoon: config.provisionalUserConfidence,
                        evening: config.provisionalUserConfidence
                    )
                    flipped.insert(hash)
                    continue
                }

                // Confirm provisional override: second event that *agrees* with the new baseline
                // while confidence is still in the provisional band → raise to user truth (0.8).
                if event.newConstraint == signature.learnedConstraint,
                   !signature.isSeededBaseline,
                   signature.meanConfidence > config.immediateCapitulationCeiling,
                   signature.meanConfidence < config.confirmedUserConfidence - 0.05 {
                    let c = config.confirmedUserConfidence
                    signature.confidence = TemporalConfidence(morning: c, afternoon: c, evening: c)
                    signature.overrideCount = 0
                    continue
                }

                if event.isSoftening {
                    emaSoftening = ema(previous: emaSoftening, sample: 1.0, alpha: config.emaAlpha)
                    emaHardening = ema(previous: emaHardening, sample: 0.0, alpha: config.emaAlpha)
                    applyConfidenceDecay(
                        &signature.confidence,
                        primary: event.timeOfDay,
                        primaryDelta: -config.primaryConfidenceDelta,
                        secondaryDelta: -config.secondaryConfidenceDelta
                    )
                } else if event.isHardening {
                    emaHardening = ema(previous: emaHardening, sample: 1.0, alpha: config.emaAlpha)
                    emaSoftening = ema(previous: emaSoftening, sample: 0.0, alpha: config.emaAlpha)
                    applyConfidenceDecay(
                        &signature.confidence,
                        primary: event.timeOfDay,
                        primaryDelta: -config.primaryConfidenceDelta * 0.8,
                        secondaryDelta: -config.secondaryConfidenceDelta * 0.5
                    )
                } else {
                    signature.confidence.adjust(event.timeOfDay, by: -config.primaryConfidenceDelta * 0.5)
                }

                // High-confidence baselines still need repeated evidence.
                // Reset overrideTicks + EMA after a flip so one batch of softens
                // cannot cascade anchored → flexible → fluid without fresh strikes.
                if overrideTicks >= config.baselineFlipThreshold {
                    if emaSoftening > emaHardening, emaSoftening >= 0.55 {
                        let candidate = signature.learnedConstraint.softened()
                        if candidate != signature.learnedConstraint {
                            signature.learnedConstraint = candidate
                            signature.overrideCount = 0
                            signature.isSeededBaseline = false
                            signature.confidence = boostedConfidence(around: event.timeOfDay, base: 0.55)
                            flipped.insert(hash)
                            overrideTicks = 0
                            emaSoftening = 0
                            emaHardening = 0
                        }
                    } else if emaHardening > emaSoftening, emaHardening >= 0.55 {
                        let candidate = signature.learnedConstraint.hardened()
                        if candidate != signature.learnedConstraint {
                            signature.learnedConstraint = candidate
                            signature.overrideCount = 0
                            signature.isSeededBaseline = false
                            signature.confidence = boostedConfidence(around: event.timeOfDay, base: 0.55)
                            flipped.insert(hash)
                            overrideTicks = 0
                            emaSoftening = 0
                            emaHardening = 0
                        }
                    }
                }
            }

            signature.state = .active
            signature.lastUpdated = now
            nextVault.upsert(signature, now: now)
            updated.insert(hash)
        }

        // Touch active schedule hashes (also resurrects dormant if scheduled again).
        for hash in activeScheduleHashes {
            if var sig = nextVault.signature(for: hash) {
                sig.lastSeenInSchedule = now
                sig.state = .active
                nextVault.upsert(sig, now: now)
            }
        }

        let pruned = applyProgressivePruning(
            vault: &nextVault,
            activeScheduleHashes: activeScheduleHashes.union(updated),
            now: now,
            config: config
        )

        return TelemetrySynthesisResult(
            vault: nextVault,
            consumedDayKeys: consumedDayKeys.sorted(),
            processedEventCount: events.count,
            updatedHashes: updated.sorted(),
            flippedHashes: flipped.sorted(),
            prunedHashes: pruned.sorted()
        )
    }

    /// 30-day dormancy + 15-day dormant deletion (45 total). Active schedule is never pruned.
    @discardableResult
    public static func applyProgressivePruning(
        vault: inout BehavioralVaultEnvelope,
        activeScheduleHashes: Set<String>,
        now: Date,
        config: TelemetrySynthesizerConfig = .default
    ) -> [String] {
        let dormantCutoff = now.addingTimeInterval(-Double(config.dormancyDays) * 86_400)
        let deleteCutoff = now.addingTimeInterval(
            -Double(config.dormancyDays + config.dormantDeletionDays) * 86_400
        )
        var deleted: [String] = []

        for idx in vault.signatures.indices {
            var sig = vault.signatures[idx]
            if activeScheduleHashes.contains(sig.semanticHash) {
                sig.state = .active
                vault.signatures[idx] = sig
                continue
            }
            let anchor = sig.lastSeenInSchedule ?? sig.lastUpdated
            switch sig.state {
            case .active:
                if anchor < dormantCutoff {
                    sig.state = .dormant(since: now)
                    vault.signatures[idx] = sig
                }
            case .dormant(let since):
                // Delete if dormant period itself aged out, or total inactivity past 45d.
                if since <= now.addingTimeInterval(-Double(config.dormantDeletionDays) * 86_400)
                    || anchor < deleteCutoff {
                    deleted.append(sig.semanticHash)
                }
            }
        }

        if !deleted.isEmpty {
            vault.signatures.removeAll { deleted.contains($0.semanticHash) }
            vault.updatedAt = now
        }
        return deleted
    }

    /// Backward-compatible alias used by older call sites/tests.
    @discardableResult
    public static func pruneInactiveSignatures(
        vault: inout BehavioralVaultEnvelope,
        activeScheduleHashes: Set<String>,
        now: Date,
        inactivityDays: Int
    ) -> [String] {
        var config = TelemetrySynthesizerConfig.default
        // Map legacy single threshold → dormancy at inactivity-15, delete at inactivity.
        config.dormantDeletionDays = 15
        config.dormancyDays = max(inactivityDays - 15, 1)
        return applyProgressivePruning(
            vault: &vault,
            activeScheduleHashes: activeScheduleHashes,
            now: now,
            config: config
        )
    }

    public static func isStarved(
        vault: BehavioralVaultEnvelope,
        now: Date = Date(),
        config: TelemetrySynthesizerConfig = .default
    ) -> Bool {
        now.timeIntervalSince(vault.updatedAt) >= config.starvationAge
    }

    // MARK: - Math helpers

    public static func ema(previous: Double, sample: Double, alpha: Double) -> Double {
        alpha * sample + (1 - alpha) * previous
    }

    public static func applyConfidenceDecay(
        _ confidence: inout TemporalConfidence,
        primary: BehavioralTimeOfDay,
        primaryDelta: Double,
        secondaryDelta: Double
    ) {
        for bucket in BehavioralTimeOfDay.allCases {
            if bucket == primary {
                confidence.adjust(bucket, by: primaryDelta)
            } else {
                confidence.adjust(bucket, by: secondaryDelta)
            }
        }
    }

    private static func boostedConfidence(around primary: BehavioralTimeOfDay, base: Double) -> TemporalConfidence {
        var c = TemporalConfidence(morning: base, afternoon: base, evening: base)
        c[primary] = min(1, base + 0.2)
        return c
    }
}
