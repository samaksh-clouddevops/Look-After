import Foundation

/// Compiles LifeState → sanitized `BriefingPayload`. Strips PII / raw titles.
public enum BriefingPayloadCompiler {

    public struct Input: Sendable {
        public var now: Date
        public var energy: EnergyLevel
        public var energyPercent: Int?
        public var sleepHours: Double?
        public var capacityBandLabel: String
        public var tasks: [LifeTask]
        public var cascadeDecisions: [ConflictCascadeDecision]
        public var parkedRecoverableCount: Int
        public var somedayDecayCount: Int
        public var telemetryLearnings: [String]
        public var nextEventTitle: String?
        public var minutesUntilNextEvent: Int?
        public var resurrectedTaskIDs: Set<String>

        public init(
            now: Date = Date(),
            energy: EnergyLevel = .moderate,
            energyPercent: Int? = nil,
            sleepHours: Double? = nil,
            capacityBandLabel: String = "Moderate",
            tasks: [LifeTask] = [],
            cascadeDecisions: [ConflictCascadeDecision] = [],
            parkedRecoverableCount: Int = 0,
            somedayDecayCount: Int = 0,
            telemetryLearnings: [String] = [],
            nextEventTitle: String? = nil,
            minutesUntilNextEvent: Int? = nil,
            resurrectedTaskIDs: Set<String> = []
        ) {
            self.now = now
            self.energy = energy
            self.energyPercent = energyPercent
            self.sleepHours = sleepHours
            self.capacityBandLabel = capacityBandLabel
            self.tasks = tasks
            self.cascadeDecisions = cascadeDecisions
            self.parkedRecoverableCount = parkedRecoverableCount
            self.somedayDecayCount = somedayDecayCount
            self.telemetryLearnings = telemetryLearnings
            self.nextEventTitle = nextEventTitle
            self.minutesUntilNextEvent = minutesUntilNextEvent
            self.resurrectedTaskIDs = resurrectedTaskIDs
        }
    }

    public static func compile(
        _ input: Input,
        calendar: Calendar = .current
    ) -> BriefingPayload {
        let day = calendar.startOfDay(for: input.now)
        let dayKey = TelemetryLogRotation.dayKey(for: day, calendar: calendar)
        // Include expired/superseded for tallies (not only actives).
        let dayScoped = input.tasks.filter { task in
            if let d = task.scheduledDate { return calendar.isDate(d, inSameDayAs: day) }
            return task.status.isActive || task.status == .expired || task.status == .superseded
                || task.status == .skipped
        }

        var anchored = 0, flexible = 0, fluid = 0, focus = 0
        var remaining = 0, completed = 0, overdue = 0
        var hasRecovery = false
        var superseded = 0
        var expired = 0

        for task in dayScoped {
            if task.tags.contains("recovery-block") { hasRecovery = true }
            if task.status == .superseded { superseded += 1 }
            if task.status == .expired || task.status == .skipped { expired += 1 }
            guard task.status.isActive || task.status == .completed else { continue }
            switch task.timeConstraintValue {
            case .anchored: anchored += 1
            case .flexible: flexible += 1
            case .fluid: fluid += 1
            }
            if task.status.isActive {
                remaining += 1
                if task.isOverdue { overdue += 1 }
                if task.timeConstraintValue != .fluid {
                    focus += max(task.estimatedMinutes, 0)
                }
            } else if task.status == .completed {
                completed += 1
            }
        }

        // Prefer distilled overnight macros when present; else collapse raw decisions.
        let distilled = CascadeDistiller.distill(
            decisions: input.cascadeDecisions,
            triggeredRecoveryLock: hasRecovery,
            resurrectedCount: input.resurrectedTaskIDs.count
        )
        let mutations: [BriefingMutationFact]
        if distilled.isEmpty {
            mutations = collapseMutations(
                decisions: input.cascadeDecisions,
                hasRecovery: hasRecovery,
                resurrectedCount: input.resurrectedTaskIDs.count
            )
        } else {
            mutations = CascadeDistiller.mutationFacts(from: distilled)
        }

        // Merge decision-level tallies if task statuses not yet persisted.
        let decisionSuperseded = input.cascadeDecisions.filter { $0.action == .superseded }.count
        let decisionExpiredOnly = input.cascadeDecisions.filter { $0.action == .expired }.count
        expired = max(expired, decisionExpiredOnly)
        superseded = max(superseded, decisionSuperseded)

        let nextCat = input.nextEventTitle.map { BriefingPIISanitizer.category(forTitle: $0) }

        let learnings = input.telemetryLearnings
            .map { BriefingPIISanitizer.scrub($0) }
            .filter { !$0.isEmpty }
            .prefix(4)
            .map { String($0) }

        return BriefingPayload(
            generatedAt: input.now,
            dayKey: dayKey,
            energyState: input.energy.rawValue,
            energyPercent: input.energyPercent,
            sleepHours: input.sleepHours,
            capacityBand: input.capacityBandLabel,
            anchoredCount: anchored,
            flexibleCount: flexible,
            fluidCount: fluid,
            focusMinutes: focus,
            remainingTaskCount: remaining,
            completedTaskCount: completed,
            overdueCount: overdue,
            nextEventCategory: nextCat,
            minutesUntilNextEvent: input.minutesUntilNextEvent,
            mutations: mutations,
            telemetryLearnings: Array(learnings),
            somedayDecayCount: input.somedayDecayCount,
            parkedRecoverableCount: input.parkedRecoverableCount,
            hasRecoveryBlockToday: hasRecovery,
            supersededTaskCount: superseded,
            expiredTaskCount: expired
        )
    }

    private static func collapseMutations(
        decisions: [ConflictCascadeDecision],
        hasRecovery: Bool,
        resurrectedCount: Int
    ) -> [BriefingMutationFact] {
        var counts: [String: Int] = [:]
        for d in decisions {
            let code: String
            switch d.action {
            case .keep: continue
            case .shiftLater: code = "shift_later"
            case .compress: code = "compress"
            case .deferNextGap: code = "defer_gap"
            case .park: code = "park"
            case .expired: code = "expired"
            case .superseded: code = "superseded"
            }
            counts[code, default: 0] += 1
        }
        if hasRecovery { counts["sabotage_recovery", default: 0] += 1 }
        if resurrectedCount > 0 { counts["resurrect"] = resurrectedCount }

        return counts.map { BriefingMutationFact(code: $0.key, count: $0.value) }
            .sorted { $0.code < $1.code }
    }
}

// MARK: - PII sanitizer

public enum BriefingPIISanitizer {
    /// Map a raw title to a non-identifying category for external LLM payloads.
    public static func category(forTitle title: String) -> String {
        let t = title.lowercased()
        if t.contains("dr ") || t.contains("doctor") || t.contains("therapy")
            || t.contains("dentist") || t.contains("clinic") || t.contains("medical") {
            return "medical appointment"
        }
        if t.contains("standup") || t.contains("1:1") || t.contains("sync")
            || t.contains("meeting") || t.contains("call") {
            return "meeting"
        }
        if t.contains("gym") || t.contains("workout") || t.contains("run") {
            return "workout"
        }
        if t.contains("flight") || t.contains("train") || t.contains("commute") {
            return "travel"
        }
        if t.contains("recovery") { return "recovery block" }
        return "calendar block"
    }

    /// Scrub likely personal names / emails / phones from free text.
    public static func scrub(_ text: String) -> String {
        var s = text
        // emails
        s = s.replacingOccurrences(
            of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            with: "[email]",
            options: [.regularExpression, .caseInsensitive]
        )
        // phone-ish
        s = s.replacingOccurrences(
            of: #"\b\d{3}[-.\s]?\d{3}[-.\s]?\d{4}\b"#,
            with: "[phone]",
            options: .regularExpression
        )
        return s
    }
}
