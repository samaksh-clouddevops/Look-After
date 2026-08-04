import Foundation
import LookAfterCore

/// Human-readable task duration labels — estimated total vs. focus-at-a-stretch.
public struct TaskTimeDisplayInfo: Sendable, Equatable {
    public var lineLabel: String
    public var chipLabel: String
    public var usesFocusStretch: Bool
    public var focusStretchMinutes: Int
    public var needsAIRefinement: Bool

    public init(
        lineLabel: String,
        chipLabel: String,
        usesFocusStretch: Bool,
        focusStretchMinutes: Int,
        needsAIRefinement: Bool
    ) {
        self.lineLabel = lineLabel
        self.chipLabel = chipLabel
        self.usesFocusStretch = usesFocusStretch
        self.focusStretchMinutes = focusStretchMinutes
        self.needsAIRefinement = needsAIRefinement
    }
}

/// Resolves how long the user can focus at one stretch from energy, sleep, and profile signals.
public enum TaskFocusStretchResolver {

    public struct Context: Sendable {
        public var energyScore: Double
        public var sleepQuality: SleepQuality?
        public var executiveCapacity: ExecutiveCapacityState
        public var preferredFocusMinutes: Int

        public init(
            energyScore: Double = 0.55,
            sleepQuality: SleepQuality? = nil,
            executiveCapacity: ExecutiveCapacityState = .moderate,
            preferredFocusMinutes: Int = TaskDurationPolicy.defaultMinutes
        ) {
            self.energyScore = energyScore
            self.sleepQuality = sleepQuality
            self.executiveCapacity = executiveCapacity
            self.preferredFocusMinutes = preferredFocusMinutes
        }

        public static func fromProfile(
            energyScore: Double?,
            sleepQuality: SleepQuality?,
            executiveCapacity: ExecutiveCapacityState?
        ) -> Context {
            Context(
                energyScore: energyScore ?? 0.55,
                sleepQuality: sleepQuality,
                executiveCapacity: executiveCapacity ?? .moderate,
                preferredFocusMinutes: TaskDurationPolicy.defaultMinutes
            )
        }
    }

    public static func displayInfo(for task: LifeTask, context: Context) -> TaskTimeDisplayInfo {
        let stretch = recommendedFocusStretch(for: task, context: context)
        let estimated = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)

        if estimated <= stretch {
            let label = "Estimated time \(estimated) min"
            return TaskTimeDisplayInfo(
                lineLabel: label,
                chipLabel: label,
                usesFocusStretch: false,
                focusStretchMinutes: stretch,
                needsAIRefinement: false
            )
        }

        let label = "Focus for \(stretch) min at a stretch"
        return TaskTimeDisplayInfo(
            lineLabel: label,
            chipLabel: label,
            usesFocusStretch: true,
            focusStretchMinutes: stretch,
            needsAIRefinement: true
        )
    }

    public static func recommendedFocusStretch(for task: LifeTask, context: Context) -> Int {
        var minutes = context.preferredFocusMinutes

        switch context.executiveCapacity.band {
        case .recoveryMode, .lowCapacity:
            minutes = min(minutes, 12)
        case .moderateCapacity:
            minutes = min(minutes, 25)
        case .goodCapacity:
            minutes = min(minutes, 35)
        case .peakFocus:
            minutes = min(minutes, 45)
        }

        if context.energyScore < 0.35 {
            minutes = min(minutes, 15)
        } else if context.energyScore < 0.55 {
            minutes = min(minutes, 20)
        }

        if context.sleepQuality == .poor || context.sleepQuality == .fair {
            minutes = min(minutes, 15)
        }

        switch task.difficulty {
        case .intense, .hard:
            minutes = min(minutes, 25)
        case .easy, .trivial:
            minutes = min(minutes + 5, 45)
        default:
            break
        }

        switch task.resolvedSemanticProfile.semanticType {
        case .deepWork, .creative:
            minutes = min(minutes, 25)
        default:
            break
        }

        return TaskDurationPolicy.clamp(minutes)
    }
}
