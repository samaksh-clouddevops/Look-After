import Foundation
import LookAfterCore
import LookAfterAI

/// Controls when executive-capacity inference may call the LLM.
public enum ExecutiveCapacityLLMPolicy: Sendable {
    /// Local rules only — no API usage (default for UI refreshes and the context loop).
    case deterministicOnly
    /// LLM enrichment at most once per `ExecutiveCapacityEngine.minimumLLMInterval` (health sync).
    case llmIfDue
}

/// Infers Executive Capacity from LifeState — interpretive, not a HealthKit dashboard.
public final class ExecutiveCapacityEngine {
    /// Minimum spacing between automatic capacity LLM calls (~20 minutes).
    public static let minimumLLMInterval: TimeInterval = 20 * 60

    private let glm: GLMService?
    private let calendar = Calendar.current
    private let throttleLock = NSLock()
    private var lastLLMEnrichmentAt: Date?

    public init(glmService: GLMService? = nil) {
        self.glm = glmService
    }

    public func evaluate(
        _ input: ExecutiveCapacityInput,
        llmPolicy: ExecutiveCapacityLLMPolicy = .deterministicOnly
    ) async -> ExecutiveCapacityState {
        let deterministic = inferDeterministic(input)
        guard llmPolicy == .llmIfDue, let glm, isLLMDue() else { return deterministic }

        do {
            let enriched = try await enrichViaLLM(input: input, baseline: deterministic, glm: glm)
            markLLMEnrichment()
            return enriched
        } catch {
            return deterministic
        }
    }

    private func isLLMDue() -> Bool {
        throttleLock.lock()
        defer { throttleLock.unlock() }
        guard let lastLLMEnrichmentAt else { return true }
        return Date().timeIntervalSince(lastLLMEnrichmentAt) >= Self.minimumLLMInterval
    }

    private func markLLMEnrichment() {
        throttleLock.lock()
        lastLLMEnrichmentAt = Date()
        throttleLock.unlock()
    }

    /// Synchronous deterministic inference — used when AI unavailable.
    public func evaluateSync(_ input: ExecutiveCapacityInput) -> ExecutiveCapacityState {
        inferDeterministic(input)
    }

    // MARK: - Deterministic inference

    private func inferDeterministic(_ input: ExecutiveCapacityInput) -> ExecutiveCapacityState {
        let snapshot = input.snapshot
        let score = compositeScore(input)
        let band = band(for: score, input: input)
        let reasons = buildReasons(input: input, band: band, score: score)
        let work = workRecommendations(for: band)
        let forecast = buildForecast(current: band, input: input)

        return ExecutiveCapacityState(
            band: band,
            confidence: confidence(for: input),
            reasoning: CapacityReasoning(
                reasons: reasons,
                recommendedWorkTypes: work.recommended,
                avoidWorkTypes: work.avoid,
                detailSummary: detailSummary(input: input, score: score)
            ),
            forecast: forecast
        )
    }

    private func compositeScore(_ input: ExecutiveCapacityInput) -> Double {
        let snapshot = input.snapshot
        var score = snapshot?.currentEnergy ?? input.cognitiveSnapshot?.energyScore ?? 0.5
        score = score * 0.32

        let readiness = snapshot?.healthReadiness ?? input.cognitiveSnapshot?.recoveryScore ?? 0.5
        score += readiness * 0.22

        let focus = input.cognitiveSnapshot?.focusCapacity ?? 0.5
        score += focus * 0.15

        score += (snapshot?.completionProbability ?? 0.5) * 0.1

        switch snapshot?.sleepQuality ?? .unknown {
        case .good, .excellent: score += 0.12
        case .fair: score += 0.04
        case .poor: score -= 0.12
        case .unknown: break
        }

        if let sleepMin = input.healthSummary?.totalSleepMinutes {
            let hours = sleepMin / 60.0
            if hours >= 7.5 { score += 0.06 }
            else if hours < 6 { score -= 0.1 }
        }

        if let hrv = input.healthSummary?.hrvAverage, hrv < 35 {
            score -= 0.06
        }

        let cal = snapshot?.calendarAvailability
        if let until = cal?.minutesUntilNextEvent {
            if until >= 120 { score += 0.06 }
            else if until <= 25 { score -= 0.14 }
            else if until <= 60 { score -= 0.06 }
        } else if cal?.hasOpenFlowWindow == true {
            score += 0.05
        }

        if input.completedTodayCount >= 2 { score += 0.08 }
        if input.completedTodayCount >= 4 { score += 0.04 }
        if input.isInFlowSession { score += 0.05 }

        if input.meetingCountHint >= 4 { score -= 0.1 }
        if input.activeTaskCount > 12 { score -= 0.06 }

        if CyclePreferencesStore.isActive {
            let snapshot = CycleEngine.snapshot(CycleEngine.Input())
            let modifier = CycleInsightBuilder.capacityModifier(snapshot: snapshot, logs: CycleLogStore.load())
            score += Double(modifier) / 100.0
        }

        let hour = calendar.component(.hour, from: input.now)
        if hour >= 13 && hour <= 15 { score -= 0.05 }
        if hour >= 21 || hour < 6 { score -= 0.12 }

        return min(max(score, 0.05), 0.98)
    }

    private func band(for score: Double, input: ExecutiveCapacityInput) -> ExecutiveCapacityBand {
        if score >= 0.82 { return .peakFocus }
        if score >= 0.64 { return .goodCapacity }
        if score >= 0.46 { return .moderateCapacity }
        if score >= 0.30 { return .lowCapacity }
        return .recoveryMode
    }

    private func buildReasons(input: ExecutiveCapacityInput, band: ExecutiveCapacityBand, score: Double) -> [String] {
        var candidates: [(priority: Int, text: String)] = []

        switch input.snapshot?.sleepQuality ?? .unknown {
        case .good, .excellent:
            candidates.append((10, "You slept well."))
        case .fair:
            candidates.append((6, "Sleep was okay — pace yourself."))
        case .poor:
            candidates.append((10, "Sleep was short — go easier on deep work."))
        case .unknown:
            if let hours = input.healthSummary?.totalSleepMinutes.map({ $0 / 60.0 }) {
                if hours >= 7 { candidates.append((8, "You slept well.")) }
                else if hours < 6 { candidates.append((9, "Short sleep is limiting focus.")) }
            }
        }

        if let until = input.snapshot?.calendarAvailability.minutesUntilNextEvent {
            if until >= 90 {
                let label = formatUntilMeeting(until)
                candidates.append((9, "No meetings \(label)."))
            } else if until <= 30 {
                candidates.append((10, "A meeting is coming up soon."))
            }
        } else if input.snapshot?.calendarAvailability.hasOpenFlowWindow == true {
            candidates.append((8, "Your calendar is mostly open."))
        }

        if input.completedTodayCount >= 2 {
            candidates.append((7, "Momentum is building."))
        }
        if input.isInFlowSession {
            candidates.append((8, "You're already in flow."))
        }

        if input.meetingCountHint >= 4 {
            candidates.append((7, "It's a meeting-heavy day."))
        }

        if band == .recoveryMode || score < 0.35 {
            candidates.append((9, "Your body needs recovery more than output."))
        }

        if candidates.isEmpty {
            candidates.append((5, "Capacity looks steady for now."))
        }

        return candidates.sorted { $0.priority > $1.priority }.prefix(3).map(\.text)
    }

    private func workRecommendations(for band: ExecutiveCapacityBand) -> (recommended: [String], avoid: [String]) {
        switch band {
        case .peakFocus:
            return (["Deep work", "Architecture", "Complex writing"], ["Long admin blocks", "Passive meetings"])
        case .goodCapacity:
            return (["Meaningful projects", "Creative work", "Focused reviews"], ["Heavy financial planning", "Marathon meetings"])
        case .moderateCapacity:
            return (["Planning", "Email", "Light creative work"], ["Deep coding marathons", "High-stakes decisions"])
        case .lowCapacity:
            return (["Errands", "Simple tasks", "Short reviews"], ["Deep work", "Complex negotiations"])
        case .recoveryMode:
            return (["Rest", "Light tidying", "Short walks"], ["Deep work", "Big commitments", "Long meetings"])
        }
    }

    private func buildForecast(current: ExecutiveCapacityBand, input: ExecutiveCapacityInput) -> [CapacityForecastPoint] {
        let now = input.now
        let profile = UserLifeProfileStore.load()
        var points: [CapacityForecastPoint] = [
            CapacityForecastPoint(id: "now", timeLabel: "Now", band: current)
        ]

        let postPeakHour = min(max(profile.peakEndHour + 1, profile.peakEndHour), 23)
        if let postPeak = calendar.date(bySettingHour: postPeakHour, minute: 0, second: 0, of: now),
           postPeak > now {
            points.append(CapacityForecastPoint(
                id: "post-peak",
                timeLabel: formatTime(postPeak),
                band: downgrade(current, steps: 1)
            ))
        }

        let workEndHour = min(profile.workEndHour, 23)
        if let evening = calendar.date(bySettingHour: workEndHour, minute: 0, second: 0, of: now),
           evening > now {
            points.append(CapacityForecastPoint(
                id: "evening",
                timeLabel: formatTime(evening),
                band: .recoveryMode
            ))
        }

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let tomorrowMorning = calendar.date(bySettingHour: profile.workStartHour, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        let tomorrowBand: ExecutiveCapacityBand
        switch input.snapshot?.sleepQuality ?? .unknown {
        case .good, .excellent: tomorrowBand = .peakFocus
        case .fair: tomorrowBand = .goodCapacity
        case .poor: tomorrowBand = .moderateCapacity
        case .unknown: tomorrowBand = .goodCapacity
        }
        points.append(CapacityForecastPoint(
            id: "tomorrow",
            timeLabel: "Tomorrow \(formatTime(tomorrowMorning))",
            band: tomorrowBand
        ))

        return points
    }

    private func downgrade(_ band: ExecutiveCapacityBand, steps: Int) -> ExecutiveCapacityBand {
        let order: [ExecutiveCapacityBand] = [.peakFocus, .goodCapacity, .moderateCapacity, .lowCapacity, .recoveryMode]
        guard let idx = order.firstIndex(of: band) else { return band }
        return order[min(idx + steps, order.count - 1)]
    }

    private func confidence(for input: ExecutiveCapacityInput) -> Double {
        var c = 0.55
        if input.healthSummary != nil { c += 0.15 }
        if input.snapshot != nil { c += 0.15 }
        if input.cognitiveSnapshot != nil { c += 0.1 }
        return min(c, 0.92)
    }

    private func detailSummary(input: ExecutiveCapacityInput, score: Double) -> String {
        var parts: [String] = []
        if let hrv = input.healthSummary?.hrvAverage { parts.append("HRV \(Int(hrv))ms") }
        if let sleep = input.healthSummary?.totalSleepMinutes {
            parts.append("Sleep \(String(format: "%.1f", sleep / 60))h")
        }
        if let free = input.snapshot?.availableTimeMinutes { parts.append("\(free)m free today") }
        parts.append("Inference confidence \(Int(confidence(for: input) * 100))%")
        return parts.joined(separator: " · ")
    }

    private func formatUntilMeeting(_ minutes: Int) -> String {
        if minutes >= 120 {
            let h = minutes / 60
            return "for \(h)+ hours"
        }
        return "for \(minutes)m"
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h a"
        return f.string(from: date).replacingOccurrences(of: " ", with: " ")
    }

    // MARK: - LLM enrichment

    private struct LLMCapacityResponse: Codable {
        var band: String?
        var reasons: [String]?
        var recommendedWorkTypes: [String]?
        var avoidWorkTypes: [String]?
        var forecast: [LLMForecast]?
    }

    private struct LLMForecast: Codable {
        var timeLabel: String
        var band: String
    }

    private func enrichViaLLM(
        input: ExecutiveCapacityInput,
        baseline: ExecutiveCapacityState,
        glm: GLMService
    ) async throws -> ExecutiveCapacityState {
        let prompt = LookAfterPrompts.executiveCapacityPrompt(
            baselineBand: baseline.band.displayLabel,
            sleepQuality: input.snapshot?.sleepQuality.rawValue ?? "unknown",
            freeMinutes: input.snapshot?.availableTimeMinutes ?? 0,
            completedToday: input.completedTodayCount,
            activeTasks: input.activeTaskCount,
            isInFlow: input.isInFlowSession
        )

        let raw = try await glm.sendMessage(prompt, systemPrompt: LookAfterPrompts.executiveCapacitySystem, history: [], tier: .economy)
        guard let data = extractJSON(from: raw)?.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(LLMCapacityResponse.self, from: data) else {
            return baseline
        }

        var state = baseline
        if let bandLabel = decoded.band, let mapped = mapBand(label: bandLabel) {
            state.band = mapped
        }
        if let reasons = decoded.reasons, !reasons.isEmpty {
            state.reasoning.reasons = Array(reasons.prefix(3))
        }
        if let rec = decoded.recommendedWorkTypes { state.reasoning.recommendedWorkTypes = rec }
        if let avoid = decoded.avoidWorkTypes { state.reasoning.avoidWorkTypes = avoid }
        if let fc = decoded.forecast {
            state.forecast = fc.compactMap { point in
                guard let b = mapBand(label: point.band) else { return nil }
                return CapacityForecastPoint(timeLabel: point.timeLabel, band: b)
            }
        }
        return state
    }

    private func mapBand(label: String) -> ExecutiveCapacityBand? {
        let lower = label.lowercased()
        if lower.contains("peak") { return .peakFocus }
        if lower.contains("good") { return .goodCapacity }
        if lower.contains("moderate") { return .moderateCapacity }
        if lower.contains("low") { return .lowCapacity }
        if lower.contains("recovery") { return .recoveryMode }
        return nil
    }

    private func extractJSON(from raw: String) -> String? {
        let clean = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = clean.firstIndex(of: "{"), let end = clean.lastIndex(of: "}") {
            return String(clean[start...end])
        }
        return clean.isEmpty ? nil : clean
    }
}
