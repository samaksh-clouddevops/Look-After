import Foundation

/// Deterministic scheduling from semantic profiles — never from titles.
public enum TaskSemanticScheduler {

    public struct Context: Sendable {
        public var now: Date
        public var energyScore: Double
        public var sleepHours: Double?
        public var freeBlockMinutes: Int
        public var calendar: Calendar

        public init(
            now: Date = Date(),
            energyScore: Double = 0.6,
            sleepHours: Double? = nil,
            freeBlockMinutes: Int = 120,
            calendar: Calendar = .current
        ) {
            self.now = now
            self.energyScore = min(max(energyScore, 0), 1)
            self.sleepHours = sleepHours
            self.freeBlockMinutes = max(freeBlockMinutes, 0)
            self.calendar = calendar
        }
    }

    /// Whether a task may be scheduled right now given its meaning and current state.
    public static func schedulability(
        profile: TaskSemanticProfile,
        context: Context
    ) -> TaskSchedulabilityResult {
        let window = currentTimeWindow(at: context.now, calendar: context.calendar)

        if profile.forbiddenTimeWindows.contains(window) {
            return TaskSchedulabilityResult(
                isAllowed: false,
                reason: "Not schedulable during \(window.rawValue) — forbidden by task semantics"
            )
        }

        if profile.semanticType == .medication {
            if profile.schedulingConstraints.contains(.neverEveningDose),
               window == .evening || window == .night {
                return TaskSchedulabilityResult(
                    isAllowed: false,
                    reason: "Medication must not be scheduled for evening without explicit user configuration"
                )
            }
            if profile.schedulingConstraints.contains(.beforeBreakfast),
               window != .morning {
                return TaskSchedulabilityResult(
                    isAllowed: false,
                    reason: "Morning medication — wait for morning window"
                )
            }
        }

        // Deep focus / deep work after short sleep is an executive-cost failure (Brain #12).
        // Apply even when the profile omitted an explicit avoidAfterPoorSleep tag.
        if isDeepWorkCandidate(profile: profile),
           let sleep = context.sleepHours, sleep < 6 {
            return TaskSchedulabilityResult(
                isAllowed: false,
                reason: "Deep focus blocked after short sleep (\(String(format: "%.1f", sleep))h)"
            )
        }

        if profile.schedulingConstraints.contains(.avoidAfterPoorSleep),
           let sleep = context.sleepHours, sleep < 6.5,
           profile.cognitiveRequirement == .deepFocus || profile.semanticType == .deepWork {
            return TaskSchedulabilityResult(
                isAllowed: false,
                reason: "Deep focus blocked after poor sleep"
            )
        }

        if profile.cognitiveRequirement == .deepFocus,
           profile.schedulingConstraints.contains(.requiresUninterruptedBlock),
           context.freeBlockMinutes < min(profile.estimatedDuration, 45) {
            return TaskSchedulabilityResult(
                isAllowed: false,
                reason: "Needs \(min(profile.estimatedDuration, 45))+ uninterrupted minutes"
            )
        }

        // Low energy + deep work: block unless deadline consequence is medical / high.
        if isDeepWorkCandidate(profile: profile),
           context.energyScore < 0.4,
           profile.consequenceOfDelay != .medicalRisk,
           profile.consequenceOfDelay != .high {
            return TaskSchedulabilityResult(
                isAllowed: false,
                reason: "Deep work deferred — energy too low for sustained focus"
            )
        }

        let requiredEnergy = effectiveEnergyLevel(profile: profile)
        let available = EnergyLevel.from(score: context.energyScore)
        if available < requiredEnergy && profile.flexibility == .rigid {
            return TaskSchedulabilityResult(
                isAllowed: false,
                reason: "Requires \(requiredEnergy.rawValue) energy — current window is too low"
            )
        }

        return TaskSchedulabilityResult(isAllowed: true)
    }

    /// Score adjustment for ranking — positive favors scheduling now.
    public static func schedulingScoreAdjustment(
        profile: TaskSemanticProfile,
        context: Context,
        deferralCount: Int = 0
    ) -> Int {
        var score = 0
        let window = currentTimeWindow(at: context.now, calendar: context.calendar)

        if profile.preferredTimeWindows.contains(window) { score += 25 }
        if profile.preferredTimeWindows.contains(.anytime) { score += 5 }

        switch profile.consequenceOfDelay {
        case .medicalRisk: score += 80
        case .high: score += 40
        case .moderate: score += 20
        case .low: score += 5
        case .none: break
        }

        switch profile.flexibility {
        case .rigid: score += 30
        case .low: score += 15
        case .moderate, .high: break
        }

        if profile.semanticType == .medication { score += 100 }

        // Chronic deferral → prefer micro / alternate slots over hero push (Brain #L-003).
        if deferralCount >= 3 {
            score -= 40 + min(deferralCount - 3, 5) * 10
        }

        if isDeepWorkCandidate(profile: profile),
           let sleep = context.sleepHours, sleep < 6.5 {
            score -= 80
        }
        if isDeepWorkCandidate(profile: profile), context.energyScore < 0.45 {
            score -= 50
        }

        if !schedulability(profile: profile, context: context).isAllowed {
            score -= 200
        }

        return score
    }

    public static func isDeepWorkCandidate(profile: TaskSemanticProfile) -> Bool {
        profile.semanticType == .deepWork || profile.cognitiveRequirement == .deepFocus
    }

    public static func isSplittable(profile: TaskSemanticProfile, maxMinutes: Int) -> Bool {
        profile.splittable && profile.estimatedDuration > maxMinutes
    }

    public static func effectiveEnergyLevel(profile: TaskSemanticProfile) -> EnergyLevel {
        switch profile.energyRequirement {
        case .minimal, .low: return .low
        case .moderate: return .moderate
        case .high: return .high
        case .peak: return .peak
        }
    }

    public static func effectiveMinutes(profile: TaskSemanticProfile, task: LifeTask) -> Int {
        let remaining = task.remainingMinutes
        if remaining > 0 { return remaining }
        return max(profile.estimatedDuration, task.estimatedMinutes)
    }

    public static func currentTimeWindow(at date: Date, calendar: Calendar) -> TimeWindowPreference {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<11: return .morning
        case 11..<14: return .midday
        case 14..<17: return .afternoon
        case 17..<21: return .evening
        default: return .night
        }
    }
}

private extension EnergyLevel {
    static func from(score: Double) -> EnergyLevel {
        let clamped = min(max(score, 0), 1)
        if clamped <= 0.15 { return .recovery }
        if clamped <= 0.35 { return .low }
        if clamped <= 0.55 { return .moderate }
        if clamped <= 0.75 { return .high }
        return .peak
    }
}
