import Foundation
import LookAfterCore

/// AIRouter prompt compiler — injects a sanitized payload into an immutable system prompt.
public enum BriefingPromptGenerator {

    /// Immutable Chief of Staff system prompt (never mutate at runtime).
    public static let systemPrompt: String = """
    You are an elite Chief of Staff. Your tone is calm, precise, and professional. Zero emojis. Zero unsolicited advice. Synthesize the provided schedule data into a Morning Briefing (maximum 4 sentences). Explicitly mention automated schedule mutations like Sabotage Auctions or constraint softenings. If there are decayed, expired, or superseded tasks, gracefully acknowledge them and end with one brief call-to-action.
    """

    public struct CompiledPrompt: Sendable, Equatable {
        public var system: String
        public var user: String
        public var payload: BriefingRouterPayload

        public init(system: String, user: String, payload: BriefingRouterPayload) {
            self.system = system
            self.user = user
            self.payload = payload
        }
    }

    /// Compile from the strict router payload.
    public static func compile(_ payload: BriefingRouterPayload) -> CompiledPrompt {
        let actions = payload.systemActions.isEmpty
            ? "none"
            : payload.systemActions.enumerated()
                .map { "\($0.offset + 1). \(BriefingPIISanitizer.scrub($0.element))" }
                .joined(separator: "\n")

        let user = """
        SCHEDULE DATA (sanitized — no personal names or raw task titles):
        energy_state: \(payload.energyState)
        anchored_commitments_count: \(payload.anchoredCommitmentsCount)
        fluid_hours_available: \(String(format: "%.1f", payload.fluidHoursAvailable))
        decayed_task_count: \(payload.decayedTaskCount)
        superseded_task_count: \(payload.supersededTaskCount)
        expired_task_count: \(payload.expiredTaskCount)
        system_actions:
        \(actions)

        Write a Morning Briefing of at most 4 sentences. Mention system_actions when not none. Gracefully acknowledge expired/superseded counts without guilt. If decayed_task_count > 0, end with exactly one short bulk review CTA (never list items).
        """

        return CompiledPrompt(system: systemPrompt, user: user, payload: payload)
    }

    /// Compile from the full Brain payload (maps → router surface first).
    public static func compile(full: BriefingPayload) -> CompiledPrompt {
        compile(BriefingRouterPayload(from: full))
    }

    /// Run through GLM with cache + deterministic fallback.
    public static func synthesize(
        payload: BriefingRouterPayload,
        cache: BriefingNarrativeCache = .shared,
        dayKey: String = TelemetryLogRotation.dayKey(),
        forceRefresh: Bool = false,
        complete: (@Sendable (String, String) async throws -> String)? = nil
    ) async -> ChiefOfStaffBriefingSynthesizer.Result {
        let compiled = compile(payload)
        // Bridge into existing synthesizer/cache via a synthetic full payload fingerprint.
        let bridge = BriefingPayload(
            dayKey: dayKey,
            energyState: payload.energyState,
            capacityBand: payload.energyState,
            anchoredCount: payload.anchoredCommitmentsCount,
            fluidCount: Int(payload.fluidHoursAvailable.rounded()),
            focusMinutes: Int(payload.fluidHoursAvailable * 60),
            mutations: payload.systemActions.map {
                BriefingMutationFact(code: "system_action", reason: $0)
            },
            somedayDecayCount: payload.decayedTaskCount
        )

        let glmComplete: (@Sendable (String, String) async throws -> String)?
        if let completion = complete {
            let system = compiled.system
            let user = compiled.user
            glmComplete = { _, _ in
                try await completion(system, user)
            }
        } else {
            glmComplete = nil
        }
        return await ChiefOfStaffBriefingSynthesizer.synthesize(
            payload: bridge,
            userName: "",
            cache: cache,
            forceRefresh: forceRefresh,
            glmComplete: glmComplete
        )
    }
}
