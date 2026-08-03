import Foundation

/// Dynamic work-duration estimate — never a fixed Pomodoro block.
public struct DurationEstimate: Codable, Sendable, Equatable {
    public var pointMinutes: Int
    public var rangeMinMinutes: Int?
    public var rangeMaxMinutes: Int?
    public var confidence: Double
    public var factors: [String]

    public init(
        pointMinutes: Int,
        rangeMinMinutes: Int? = nil,
        rangeMaxMinutes: Int? = nil,
        confidence: Double = 0.7,
        factors: [String] = []
    ) {
        self.pointMinutes = max(1, pointMinutes)
        self.rangeMinMinutes = rangeMinMinutes
        self.rangeMaxMinutes = rangeMaxMinutes
        self.confidence = min(max(confidence, 0), 1)
        self.factors = factors
    }

    /// Human-readable time left.
    public var displayLabel: String {
        HumanLanguage.durationLabel(
            minutes: pointMinutes,
            rangeMin: rangeMinMinutes,
            rangeMax: rangeMaxMinutes,
            uncertain: confidence < 0.6
        )
    }

    public var shortLabel: String {
        if confidence < 0.6,
           let lo = rangeMinMinutes, let hi = rangeMaxMinutes, lo != hi {
            return "≈\(lo)–\(hi) min"
        }
        if pointMinutes >= 60 {
            let hours = pointMinutes / 60
            let mins = pointMinutes % 60
            if mins == 0 { return "\(hours) h" }
            return "\(hours) h \(mins) min"
        }
        return "\(pointMinutes) min"
    }
}

/// Estimates remaining work duration from task, calendar, energy, and sleep signals.
public struct DurationEstimator: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public struct Input: Sendable {
        public var task: LifeTask?
        public var snapshot: LifeContextSnapshot
        public var healthSummary: HealthSummary?
        public var title: String?
        public var priorElapsedMinutes: Int

        public init(
            task: LifeTask? = nil,
            snapshot: LifeContextSnapshot,
            healthSummary: HealthSummary? = nil,
            title: String? = nil,
            priorElapsedMinutes: Int = 0
        ) {
            self.task = task
            self.snapshot = snapshot
            self.healthSummary = healthSummary
            self.title = title
            self.priorElapsedMinutes = priorElapsedMinutes
        }
    }

    public func estimate(_ input: Input) -> DurationEstimate {
        var factors: [String] = []
        var confidence = 0.75

        let baseRemaining: Int = {
            if let task = input.task {
                let fromSteps = task.remainingMinutes
                if fromSteps > 0 {
                    factors.append("Remaining steps on task")
                    return fromSteps
                }
                if task.progress > 0 {
                    let scaled = Int(Double(task.estimatedMinutes) * (1 - task.progress))
                    factors.append("Progress already made")
                    return max(5, scaled)
                }
                factors.append("Task estimate")
                return max(TaskDurationPolicy.minimumMinutes, task.estimatedMinutes)
            }
            return 20
        }()

        var adjusted = baseRemaining

        if input.priorElapsedMinutes > 0 {
            adjusted = max(TaskDurationPolicy.minimumMinutes, adjusted - input.priorElapsedMinutes)
            factors.append("Already worked \(input.priorElapsedMinutes) min")
            confidence += 0.05
        }

        if let until = input.snapshot.calendarAvailability.minutesUntilNextEvent,
           until > 0, until < adjusted {
            adjusted = max(TaskDurationPolicy.minimumMinutes, until - 5)
            factors.append("Time until next event")
            confidence += 0.08
        } else if input.snapshot.availableTimeMinutes > 0,
                  input.snapshot.availableTimeMinutes < adjusted {
            adjusted = input.snapshot.availableTimeMinutes
            factors.append("Free time available")
        }

        if input.snapshot.sleepQuality == .poor || input.snapshot.sleepQuality == .fair {
            adjusted = Int(Double(adjusted) * 1.15)
            factors.append("Recovery day — pace may be slower")
            confidence -= 0.1
        }

        if input.snapshot.currentEnergy < 0.35 {
            adjusted = Int(Double(adjusted) * 1.1)
            factors.append("Lower energy today")
            confidence -= 0.08
        }

        adjusted = max(TaskDurationPolicy.minimumMinutes, adjusted)

        let spread = confidence < 0.6 ? max(10, Int(Double(adjusted) * 0.35)) : nil
        let rangeMin = spread.map { max(TaskDurationPolicy.minimumMinutes, adjusted - $0) }
        let rangeMax = spread.map { adjusted + $0 }

        return DurationEstimate(
            pointMinutes: adjusted,
            rangeMinMinutes: rangeMin,
            rangeMaxMinutes: rangeMax,
            confidence: min(max(confidence, 0.3), 0.95),
            factors: Array(factors.prefix(5))
        )
    }
}
