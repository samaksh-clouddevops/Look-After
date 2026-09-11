import Foundation

/// Deterministic day supervisor — fuses existing analyzers; no GLM inside the fuse step.
public enum DayAuditService {

    public struct Input: Sendable {
        public var tasks: [LifeTask]
        public var yesterdayIncomplete: [LifeTask]
        public var parkedCandidates: [ParkedTaskEntry]
        public var profile: UserLifeProfile
        public var lifeModel: LifeModel?
        public var energyPercent: Int
        public var capacityBandLabel: String
        public var referenceDate: Date
        public var now: Date
        public var calendar: Calendar
        public var maxQuestions: Int
        public var maxPulls: Int
        public var weeklyPriors: DaySupervisorPriorsStore.Priors?

        public init(
            tasks: [LifeTask],
            yesterdayIncomplete: [LifeTask] = [],
            parkedCandidates: [ParkedTaskEntry] = [],
            profile: UserLifeProfile = UserLifeProfileStore.load(),
            lifeModel: LifeModel? = LifeModelStore.load(),
            energyPercent: Int = 55,
            capacityBandLabel: String = ExecutiveCapacityBand.moderateCapacity.displayLabel,
            referenceDate: Date = Date(),
            now: Date = Date(),
            calendar: Calendar = .current,
            maxQuestions: Int = 2,
            maxPulls: Int = 3,
            weeklyPriors: DaySupervisorPriorsStore.Priors? = DaySupervisorPriorsStore.load()
        ) {
            self.tasks = tasks
            self.yesterdayIncomplete = yesterdayIncomplete
            self.parkedCandidates = parkedCandidates
            self.profile = profile
            self.lifeModel = lifeModel
            self.energyPercent = energyPercent
            self.capacityBandLabel = capacityBandLabel
            self.referenceDate = referenceDate
            self.now = now
            self.calendar = calendar
            self.maxQuestions = max(0, maxQuestions)
            self.maxPulls = max(0, maxPulls)
            self.weeklyPriors = weeklyPriors
        }
    }

    public static func run(_ input: Input) -> DayAuditResult {
        let day = input.calendar.startOfDay(for: input.referenceDate)
        var faults: [DayAuditFault] = []
        var proposed: [DayAuditFix] = []
        var questions: [DayAuditQuestion] = []

        // 1) Overlaps — report only; cascade owns repair on reconcile.
        if DayScheduleReconciler.hasOverlap(input.tasks, on: day, calendar: input.calendar) {
            faults.append(DayAuditFault(
                severity: .high,
                message: "Some blocks overlap — the schedule will untangle them when you start.",
                sourceKind: .overlap,
                needsJudgment: false
            ))
        }

        // 2) Pre-window fit → shrink / skip proposals.
        if let fit = PreWindowFitAnalyzer.analyze(
            tasks: input.tasks,
            now: input.now,
            calendar: input.calendar
        ), fit.isOvercommitted {
            faults.append(DayAuditFault(
                severity: .high,
                message: fit.summaryLine,
                relatedTaskIDs: fit.skipTaskIDs + fit.shrinkSuggestions.map(\.taskID),
                sourceKind: .preWindowFit,
                needsJudgment: true
            ))
            for shrink in fit.shrinkSuggestions {
                proposed.append(DayAuditFix(
                    kind: .shrinkTask,
                    taskID: shrink.taskID,
                    title: shrink.title,
                    detail: "Shrink \(shrink.currentMinutes)m → \(shrink.suggestedMinutes)m",
                    suggestedMinutes: shrink.suggestedMinutes
                ))
            }
            for skipID in fit.skipTaskIDs {
                let title = input.tasks.first(where: { $0.id == skipID })?.title ?? "Task"
                proposed.append(DayAuditFix(
                    kind: .skipTask,
                    taskID: skipID,
                    title: title,
                    detail: "Skip before \(fit.anchor.title)"
                ))
            }
        }

        // 3) Proactive schedule sanity / energy.
        let proactive = ScheduleProactiveAnalyzer.analyze(
            ScheduleProactiveAnalyzer.Input(
                tasks: input.tasks,
                profile: input.profile,
                lifeModel: input.lifeModel,
                referenceDate: input.referenceDate,
                now: input.now,
                energyPercent: input.energyPercent,
                calendar: input.calendar
            )
        )
        for suggestion in proactive {
            let judgment = Self.needsJudgment(kind: suggestion.kind)
            let fault = DayAuditFault(
                severity: mapSeverity(suggestion.severity),
                message: suggestion.message,
                relatedTaskIDs: suggestion.relatedTaskIDs,
                sourceKind: .proactive,
                needsJudgment: judgment
            )
            faults.append(fault)
            if judgment, questions.count < input.maxQuestions {
                questions.append(DayAuditQuestion(
                    prompt: suggestion.message,
                    options: suggestion.options,
                    relatedFaultID: fault.id,
                    relatedTaskIDs: suggestion.relatedTaskIDs
                ))
            }
        }

        // 4) Capacity vs booked flex.
        let capacity = capacitySummary(for: input, on: day)
        if capacity.isOverloaded {
            faults.append(DayAuditFault(
                severity: .high,
                message: capacity.line,
                sourceKind: .capacity,
                needsJudgment: true
            ))
            if questions.count < input.maxQuestions {
                questions.append(DayAuditQuestion(
                    prompt: "Today looks heavy for your energy. What should we protect?",
                    options: ["Keep deep work", "Cut flex work", "Keep as planned"],
                    relatedTaskIDs: []
                ))
            }
        }

        if let priors = input.weeklyPriors, priors.preferLighterMornings {
            faults.append(DayAuditFault(
                severity: .medium,
                message: priors.note.isEmpty
                    ? "Last week suggested lighter mornings — watch the early stack."
                    : "From last week: \(priors.note)",
                sourceKind: .capacity,
                needsJudgment: false
            ))
        }

        // 5) Parked / yesterday pulls vs remaining flex.
        let (possible, notPossible) = pullCandidates(for: input, remainingFlex: capacity.remainingFlexMinutes)

        // Cap questions hard at maxQuestions (already gated while appending).
        let cappedQuestions = Array(questions.prefix(input.maxQuestions))

        // Dedupe faults by message prefix to avoid noisy cards.
        let dedupedFaults = dedupeFaults(faults)

        return DayAuditResult(
            faults: dedupedFaults,
            possiblePulls: possible,
            notPossible: notPossible,
            capacitySummary: capacity,
            clarifyingQuestions: cappedQuestions,
            proposedFixes: proposed,
            safeAutoFixes: [],
            generatedAt: input.now
        )
    }

    // MARK: - Helpers

    private static func needsJudgment(kind: ScheduleProactiveSuggestion.Kind) -> Bool {
        switch kind {
        case .workOnRestDay,
             .highFocusDuringLowEnergy,
             .overloadedAfternoon,
             .initiationHeavyStack,
             .preSleepCrunch,
             .morningPlanReview:
            return true
        default:
            return false
        }
    }

    private static func mapSeverity(_ severity: ScheduleProactiveSuggestion.Severity) -> DayAuditFault.Severity {
        switch severity {
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        }
    }

    private static func capacitySummary(for input: Input, on day: Date) -> DayAuditCapacitySummary {
        let flex = input.tasks.filter { task in
            guard task.status.isActive, task.isSchedulerMovable else { return false }
            if let scheduledDate = task.scheduledDate {
                return input.calendar.isDate(scheduledDate, inSameDayAs: day)
            }
            return input.calendar.isDateInToday(day)
        }
        let booked = flex.reduce(0) { partial, task in
            partial + max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
        }
        // Rough remaining day budget from energy: low energy → ~90m flex, moderate 180, high 270.
        let budget: Int
        switch input.energyPercent {
        case ..<35: budget = 90
        case ..<60: budget = 180
        default: budget = 270
        }
        let remaining = max(0, budget - booked)
        let overloaded = booked > budget && booked - budget >= 30
        return DayAuditCapacitySummary(
            bandLabel: input.capacityBandLabel,
            energyPercent: input.energyPercent,
            bookedFlexMinutes: booked,
            remainingFlexMinutes: remaining,
            isOverloaded: overloaded
        )
    }

    private static func pullCandidates(
        for input: Input,
        remainingFlex: Int
    ) -> (possible: [DayAuditPullCandidate], notPossible: [DayAuditPullCandidate]) {
        var possible: [DayAuditPullCandidate] = []
        var notPossible: [DayAuditPullCandidate] = []

        let auctionContext = GapAuctionContext(
            energy: energyLevel(from: input.energyPercent),
            gapMinutes: max(remainingFlex, 15),
            now: input.now
        )

        for entry in input.parkedCandidates.prefix(8) {
            let minutes = max(entry.originalDurationMinutes, TaskDurationPolicy.minimumMinutes)
            let score = GapAuctionEngine.score(entry, context: auctionContext)
            let candidate = DayAuditPullCandidate(
                taskID: entry.taskID,
                title: entry.title,
                origin: .parked,
                estimatedMinutes: minutes,
                score: score
            )
            if minutes <= remainingFlex + 10 {
                possible.append(candidate)
            } else {
                notPossible.append(candidate)
            }
        }

        for task in input.yesterdayIncomplete.prefix(8) {
            let minutes = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
            let candidate = DayAuditPullCandidate(
                taskID: task.id,
                title: task.title,
                origin: .yesterday,
                estimatedMinutes: minutes,
                score: Double(task.priority.rawValue)
            )
            if minutes <= remainingFlex + 10 {
                possible.append(candidate)
            } else {
                notPossible.append(candidate)
            }
        }

        possible.sort { $0.score > $1.score }
        notPossible.sort { $0.estimatedMinutes < $1.estimatedMinutes }
        return (
            Array(possible.prefix(input.maxPulls)),
            Array(notPossible.prefix(input.maxPulls))
        )
    }

    private static func energyLevel(from percent: Int) -> EnergyLevel {
        switch percent {
        case ..<30: return .low
        case ..<50: return .moderate
        case ..<75: return .high
        default: return .peak
        }
    }

    private static func dedupeFaults(_ faults: [DayAuditFault]) -> [DayAuditFault] {
        var seen = Set<String>()
        var result: [DayAuditFault] = []
        for fault in faults.sorted(by: { severityRank($0.severity) > severityRank($1.severity) }) {
            let key = String(fault.message.prefix(48))
            guard seen.insert(key).inserted else { continue }
            result.append(fault)
        }
        return Array(result.prefix(8))
    }

    private static func severityRank(_ severity: DayAuditFault.Severity) -> Int {
        switch severity {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        }
    }
}
