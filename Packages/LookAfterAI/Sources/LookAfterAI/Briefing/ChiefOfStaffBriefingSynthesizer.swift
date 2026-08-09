import Foundation
import LookAfterCore

// MARK: - Cache

public struct BriefingNarrativeCacheEntry: Codable, Sendable, Equatable {
    public var dayKey: String
    public var fingerprint: String
    public var narrative: String
    public var source: String // "ai" | "deterministic"
    public var savedAt: Date
}

public final class BriefingNarrativeCache: @unchecked Sendable {
    public static let shared = BriefingNarrativeCache()

    private let lock = NSLock()
    private var entry: BriefingNarrativeCacheEntry?
    private let fileURL: URL?

    public init(directory: URL? = nil) {
        if let directory {
            fileURL = directory.appendingPathComponent("briefing_narrative_cache.json")
        } else if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            fileURL = support.appendingPathComponent("briefing_narrative_cache.json")
        } else {
            fileURL = nil
        }
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let loaded = try? SharedFormatters.jsonDecoderSeconds.decode(BriefingNarrativeCacheEntry.self, from: data) {
            entry = loaded
        }
    }

    public func cached(for payload: BriefingPayload) -> BriefingNarrativeCacheEntry? {
        lock.lock(); defer { lock.unlock() }
        guard let entry,
              entry.dayKey == payload.dayKey,
              entry.fingerprint == payload.structureFingerprint else {
            return nil
        }
        return entry
    }

    public func save(payload: BriefingPayload, narrative: String, source: String) {
        let e = BriefingNarrativeCacheEntry(
            dayKey: payload.dayKey,
            fingerprint: payload.structureFingerprint,
            narrative: narrative,
            source: source,
            savedAt: Date()
        )
        lock.lock()
        entry = e
        lock.unlock()
        if let fileURL, let data = try? SharedFormatters.jsonEncoderSeconds.encode(e) {
            try? data.write(to: fileURL, options: [.atomic])
        }
    }

    public func clear() {
        lock.lock(); entry = nil; lock.unlock()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }
}

// MARK: - Synthesizer

/// Payload → max 4 sentences. Cache-aware, timeout-safe, PII-free.
public enum ChiefOfStaffBriefingSynthesizer {

    public struct Result: Sendable, Equatable {
        public var narrative: String
        public var source: String
        public var fromCache: Bool
        public var chips: [BriefingSnapshotChip]

        public init(narrative: String, source: String, fromCache: Bool, chips: [BriefingSnapshotChip]) {
            self.narrative = narrative
            self.source = source
            self.fromCache = fromCache
            self.chips = chips
        }
    }

    public static func synthesize(
        payload: BriefingPayload,
        userName: String = "",
        cache: BriefingNarrativeCache = .shared,
        forceRefresh: Bool = false,
        glmComplete: ((String, String) async throws -> String)? = nil
    ) async -> Result {
        let chips = payload.snapshotChips()
        let fallback = payload.deterministicNarrative(userName: userName)

        if !forceRefresh, let hit = cache.cached(for: payload), !hit.narrative.isEmpty {
            return Result(narrative: hit.narrative, source: hit.source, fromCache: true, chips: chips)
        }

        guard let glmComplete else {
            cache.save(payload: payload, narrative: fallback, source: "deterministic")
            return Result(narrative: fallback, source: "deterministic", fromCache: false, chips: chips)
        }

        do {
            let raw = try await glmComplete(
                LookAfterPrompts.chiefOfStaffBriefingSystem,
                buildUserPrompt(payload: payload, userName: userName)
            )
            let narrative = polish(raw, fallback: fallback)
            cache.save(payload: payload, narrative: narrative, source: "ai")
            return Result(narrative: narrative, source: "ai", fromCache: false, chips: chips)
        } catch {
            cache.save(payload: payload, narrative: fallback, source: "deterministic")
            return Result(narrative: fallback, source: "deterministic", fromCache: false, chips: chips)
        }
    }

    public static func buildUserPrompt(payload: BriefingPayload, userName: String) -> String {
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let mutations = payload.mutations.isEmpty
            ? "none"
            : payload.mutations.map { "\($0.code) x\($0.count)" }.joined(separator: "; ")
        let learnings = payload.telemetryLearnings.isEmpty
            ? "none"
            : payload.telemetryLearnings.joined(separator: "; ")

        return """
        FACTS (no raw names or titles — categories only):
        user_first_name: \(name.isEmpty ? "none" : name)
        energy_state: \(payload.energyState)
        energy_percent: \(payload.energyPercent.map(String.init) ?? "unknown")
        sleep_hours: \(payload.sleepHours.map { String(format: "%.1f", $0) } ?? "unknown")
        capacity_band: \(payload.capacityBand)
        anchored_count: \(payload.anchoredCount)
        flexible_count: \(payload.flexibleCount)
        fluid_count: \(payload.fluidCount)
        focus_minutes: \(payload.focusMinutes)
        remaining_tasks: \(payload.remainingTaskCount)
        completed_tasks: \(payload.completedTaskCount)
        overdue_count: \(payload.overdueCount)
        next_event_category: \(payload.nextEventCategory ?? "none")
        minutes_until_next: \(payload.minutesUntilNextEvent.map(String.init) ?? "none")
        schedule_mutations: \(mutations)
        telemetry_learnings: \(learnings)
        parked_recoverable: \(payload.parkedRecoverableCount)
        someday_decay_count: \(payload.somedayDecayCount)
        recovery_block_locked: \(payload.hasRecoveryBlockToday)

        Write max 4 sentences. Mention mutations if present. If someday_decay_count > 0 end with one bulk action.
        """
    }

    private static func polish(_ raw: String, fallback: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Prefer "narrative" JSON field if present.
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
           let data = String(text[start...end]).data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let narrative = obj["narrative"] as? String {
            text = narrative
        }
        text = text
            .replacingOccurrences(of: "—", with: ". ")
            .replacingOccurrences(of: "–", with: ". ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Cap at ~4 sentences.
        let parts = text.components(separatedBy: ". ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.isEmpty { return fallback }
        let limited = parts.prefix(4).map { $0.hasSuffix(".") ? $0 : $0 + "." }
        return limited.joined(separator: " ")
    }
}
