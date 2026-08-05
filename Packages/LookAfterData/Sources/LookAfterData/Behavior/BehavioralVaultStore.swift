import Foundation
import LookAfterCore

/// Persistence for the Behavioral Vault (learned signatures).
/// Segregated from operational task storage and from the append-only telemetry log.
public actor BehavioralVaultStore {
    public static let sharedFileName = "behavioral_vault.json"

    private let fileURL: URL
    private var envelope: BehavioralVaultEnvelope

    public init(directory: URL? = nil, fileName: String = BehavioralVaultStore.sharedFileName) {
        let dir = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent(fileName)
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(BehavioralVaultEnvelope.self, from: data) {
            envelope = loaded
        } else {
            envelope = .empty()
        }
    }

    /// In-memory vault for tests.
    public init(envelope: BehavioralVaultEnvelope) {
        fileURL = URL(fileURLWithPath: "/dev/null")
        self.envelope = envelope
    }

    public func currentEnvelope() -> BehavioralVaultEnvelope {
        envelope
    }

    public func signature(for hash: String) -> BehavioralSignature? {
        envelope.signature(for: hash)
    }

    public func replace(_ envelope: BehavioralVaultEnvelope) {
        self.envelope = envelope
        persist()
    }

    public func upsert(_ signature: BehavioralSignature) {
        envelope.upsert(signature)
        persist()
    }

    /// Amnesia protocol — drop one hash back to factory defaults (absent signature).
    @discardableResult
    public func resetSignature(for hash: String) -> Bool {
        let changed = BehavioralAmnesia.resetSignature(for: hash, envelope: &envelope)
        if changed { persist() }
        return changed
    }

    /// Ingest **all sealed** day logs (time-agnostic). Today’s open file is never read.
    @discardableResult
    public func synthesize(
        logger: InteractionTelemetryLogger,
        activeScheduleHashes: Set<String> = [],
        now: Date = Date(),
        config: TelemetrySynthesizerConfig = .default
    ) -> TelemetrySynthesisResult {
        let sealed = logger.sealedLogs(excludingDayKey: nil)
        let result = TelemetrySynthesizer.synthesizeDailyTelemetry(
            sealedLogs: sealed,
            vault: envelope,
            activeScheduleHashes: activeScheduleHashes,
            now: now,
            config: config
        )
        envelope = result.vault
        if !result.consumedDayKeys.isEmpty {
            logger.deleteSealedLogs(dayKeys: result.consumedDayKeys)
        }
        persist()
        return result
    }

    public func isStarved(now: Date = Date(), config: TelemetrySynthesizerConfig = .default) -> Bool {
        TelemetrySynthesizer.isStarved(vault: envelope, now: now, config: config)
    }

    /// Day-1 intelligence: seed from calendar rhythm when vault is empty (confidence 0.2).
    @discardableResult
    public func seedFromCalendarHistory(
        events: [CalendarHistoryEvent],
        metaByID: [String: CalendarEventSourceMeta] = [:],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (seeded: Bool, profile: RhythmProfile) {
        let result = BehavioralVaultSeeder.seedFromCalendarHistory(
            events: events,
            metaByID: metaByID,
            envelope: &envelope,
            now: now,
            calendar: calendar
        )
        if result.seeded { persist() }
        return result
    }

    @discardableResult
    public func seedFromRhythmProfile(_ profile: RhythmProfile, now: Date = Date()) -> Bool {
        let seeded = BehavioralVaultSeeder.seedIfEmpty(profile: profile, envelope: &envelope, now: now)
        if seeded { persist() }
        return seeded
    }

    private func persist() {
        guard fileURL.path != "/dev/null",
              let data = try? JSONEncoder().encode(envelope) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
