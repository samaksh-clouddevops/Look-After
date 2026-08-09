import Foundation
import LookAfterCore
import LookAfterAI

public struct WeeklyAIRetrospective: Sendable, Equatable, Codable {
    public var narrative: String
    public var wins: [String]
    public var frictionPatterns: [String]
    public var experimentForNextWeek: String
    public var generatedAt: Date
    public var source: String

    public init(
        narrative: String,
        wins: [String] = [],
        frictionPatterns: [String] = [],
        experimentForNextWeek: String = "",
        generatedAt: Date = Date(),
        source: String = "ai"
    ) {
        self.narrative = narrative
        self.wins = wins
        self.frictionPatterns = frictionPatterns
        self.experimentForNextWeek = experimentForNextWeek
        self.generatedAt = generatedAt
        self.source = source
    }
}

/// LLM weekly synthesis with deterministic fallback.
public final class WeeklyAIRetrospectiveGenerator {
    private let glm: GLMService

    public init(glmService: GLMService = .shared) {
        self.glm = glmService
    }

    public func generate(
        summary: WeeklyReviewSummary,
        analytics: CachedAIContextSummary?,
        behaviorMemory: BehaviorMemorySnapshot
    ) async -> WeeklyAIRetrospective {
        let cacheKey = "weekly_ai_retro_\(summary.weekStartDate.timeIntervalSince1970)"
        if let cached = loadCached(key: cacheKey) { return cached }

        let cascadeCount = summary.sabotageAuctionsTriggered + summary.tasksSupersededCount + summary.tasksExpiredCount
        let prompt = """
        Write a compassionate weekly retrospective for an ADHD user.
        Focus hours: \(String(format: "%.1f", summary.totalFocusHoursCompleted))
        Time reclaimed: \(String(format: "%.1f", summary.timeReclaimedHours))h
        Cascade actions: \(cascadeCount)
        Deferrals this week: \(behaviorMemory.deferralRecords.count)
        Analytics: \(analytics?.promptBlock ?? "none")
        Return JSON: {"narrative":"...","wins":["..."],"frictionPatterns":["..."],"experimentForNextWeek":"..."}
        """

        do {
            let raw = try await glm.sendMessage(prompt, systemPrompt: "Return only valid JSON.", history: [], tier: .standard)
            if let retro = parse(raw) {
                saveCached(retro, key: cacheKey)
                persistExperiment(retro)
                return retro
            }
        } catch {
            print("[WeeklyRetro] AI unavailable: \(error.localizedDescription)")
        }

        return offlineFallback(summary: summary, behaviorMemory: behaviorMemory)
    }

    private func finalize(_ retro: WeeklyAIRetrospective) -> WeeklyAIRetrospective {
        persistExperiment(retro)
        return retro
    }

    private func parse(_ raw: String) -> WeeklyAIRetrospective? {
        let clean = raw.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        guard let start = clean.firstIndex(of: "{"), let end = clean.lastIndex(of: "}"),
              let data = String(clean[start...end]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let narrative = json["narrative"] as? String else { return nil }
        return WeeklyAIRetrospective(
            narrative: narrative,
            wins: json["wins"] as? [String] ?? [],
            frictionPatterns: json["frictionPatterns"] as? [String] ?? [],
            experimentForNextWeek: json["experimentForNextWeek"] as? String ?? "",
            source: "ai"
        )
    }

    private func persistExperiment(_ retro: WeeklyAIRetrospective) {
        guard !retro.experimentForNextWeek.isEmpty else { return }
        let weekKey = ExperimentFollowThroughDetector.weekKey(for: Date(), calendar: .current)
        ExperimentReminderStore.save(experiment: retro.experimentForNextWeek, weekKey: weekKey)
    }

    private func offlineFallback(summary: WeeklyReviewSummary, behaviorMemory: BehaviorMemorySnapshot) -> WeeklyAIRetrospective {
        let cascadeCount = summary.sabotageAuctionsTriggered + summary.tasksSupersededCount
        let narrative: String
        if summary.totalFocusHoursCompleted >= 5 {
            narrative = "Solid week — you protected \(String(format: "%.1f", summary.totalFocusHoursCompleted)) focus hours and reclaimed \(String(format: "%.1f", summary.timeReclaimedHours)) hours through smart deferrals."
        } else {
            narrative = "A lighter week is still progress. Your system handled \(cascadeCount) cascade actions to keep the load manageable."
        }
        var friction: [String] = []
        if behaviorMemory.deferralRecords.count >= 5 {
            friction.append("Several tasks were deferred multiple times — consider smaller first steps.")
        }
        return finalize(WeeklyAIRetrospective(
            narrative: narrative,
            wins: summary.totalFocusHoursCompleted >= 3 ? ["Protected focus time"] : [],
            frictionPatterns: friction,
            experimentForNextWeek: "Try batching life admin into one 15-minute block mid-week.",
            source: "offline"
        ))
    }

    private func loadCached(key: String) -> WeeklyAIRetrospective? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let retro = try? SharedFormatters.jsonDecoderSeconds.decode(WeeklyAIRetrospective.self, from: data) else { return nil }
        return retro
    }

    private func saveCached(_ retro: WeeklyAIRetrospective, key: String) {
        if let data = try? SharedFormatters.jsonEncoderSeconds.encode(retro) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
