import Foundation

public enum ContinueSessionPhase: String, Sendable {
    case restoring
    case workspace
    case active
    case failed
}

/// Context restored when the user chooses to continue — not a Pomodoro session.
public struct ContinueSessionContext: Sendable, Equatable {
    public var workingContext: WorkingContext
    public var task: LifeTask?
    public var resumeSnapshot: ResumeSnapshot?
    public var durationEstimate: DurationEstimate
    public var restorationMessage: String
    public var restartTaxSeconds: Int
    public var priorElapsedMinutes: Int
    public var insights: [RecommendationInsight]
    public var confidenceScore: Double
    public var restorationSteps: [String]

    public init(
        workingContext: WorkingContext,
        task: LifeTask? = nil,
        resumeSnapshot: ResumeSnapshot? = nil,
        durationEstimate: DurationEstimate,
        restorationMessage: String,
        restartTaxSeconds: Int = 15,
        priorElapsedMinutes: Int = 0,
        insights: [RecommendationInsight] = [],
        confidenceScore: Double = 0.8,
        restorationSteps: [String] = []
    ) {
        self.workingContext = workingContext
        self.task = task
        self.resumeSnapshot = resumeSnapshot
        self.durationEstimate = durationEstimate
        self.restorationMessage = restorationMessage
        self.restartTaxSeconds = restartTaxSeconds
        self.priorElapsedMinutes = priorElapsedMinutes
        self.insights = insights
        self.confidenceScore = confidenceScore
        self.restorationSteps = restorationSteps
    }

    public static func build(
        from resume: ResumeSnapshot?,
        task: LifeTask?,
        snapshot: LifeContextSnapshot,
        healthSummary: HealthSummary?,
        insights: [RecommendationInsight],
        confidenceScore: Double
    ) -> ContinueSessionContext? {
        let working: WorkingContext? = {
            if let ctx = resume?.workingContext { return ctx }
            if let task { return WorkingContext(kind: .task, title: task.title, taskID: task.id) }
            if let title = resume?.lastTaskTitle {
                return WorkingContext(kind: .task, title: title, taskID: resume?.lastTaskID)
            }
            return nil
        }()
        guard let context = working else { return nil }

        let priorMinutes = (resume?.lastTimerElapsedSeconds ?? 0) / 60
        let estimate = DurationEstimator().estimate(
            DurationEstimator.Input(
                task: task,
                snapshot: snapshot,
                healthSummary: healthSummary,
                title: context.title,
                priorElapsedMinutes: priorMinutes
            )
        )

        let message = restorationMessage(for: context, resume: resume)
        let steps = HumanLanguage.restorationSteps(
            for: context,
            resume: resume,
            snapshot: snapshot,
            task: task
        )

        return ContinueSessionContext(
            workingContext: context,
            task: task,
            resumeSnapshot: resume,
            durationEstimate: estimate,
            restorationMessage: message,
            restartTaxSeconds: estimatedRestartSeconds(for: context),
            priorElapsedMinutes: priorMinutes,
            insights: insights,
            confidenceScore: confidenceScore,
            restorationSteps: steps
        )
    }

    /// Always produces a session context — never silently fails the primary CTA.
    public static func buildOrFallback(
        from resume: ResumeSnapshot?,
        task: LifeTask?,
        snapshot: LifeContextSnapshot,
        healthSummary: HealthSummary?,
        insights: [RecommendationInsight],
        confidenceScore: Double,
        fallbackTitle: String
    ) -> ContinueSessionContext {
        if let built = build(
            from: resume,
            task: task,
            snapshot: snapshot,
            healthSummary: healthSummary,
            insights: insights,
            confidenceScore: confidenceScore
        ) {
            return built
        }

        let title = task?.title ?? resume?.workingContext?.title ?? resume?.lastTaskTitle ?? fallbackTitle
        let working = WorkingContext(
            kind: resume?.workingContext?.kind ?? .task,
            title: title,
            taskID: task?.id ?? resume?.lastTaskID
        )
        return ContinueSessionContext(
            workingContext: working,
            task: task,
            resumeSnapshot: resume,
            durationEstimate: DurationEstimator().estimate(
                DurationEstimator.Input(
                    task: task,
                    snapshot: snapshot,
                    healthSummary: healthSummary,
                    title: title
                )
            ),
            restorationMessage: "Restoring your workspace…",
            restartTaxSeconds: 1,
            insights: insights,
            confidenceScore: confidenceScore,
            restorationSteps: HumanLanguage.restorationSteps(
                for: working,
                resume: resume,
                snapshot: snapshot,
                task: task
            )
        )
    }

    private static func restorationMessage(for context: WorkingContext, resume: ResumeSnapshot?) -> String {
        switch context.kind {
        case .document: return "Restoring \(context.title)…"
        case .note: return "Restoring your note…"
        case .browser: return "Restoring your last link…"
        case .aiCoach: return "Restoring your conversation…"
        case .file: return "Restoring \(context.title)…"
        case .focusSession, .task:
            if let resume, !Calendar.current.isDateInToday(resume.savedAt) {
                return "Restoring yesterday's work…"
            }
            return "Restoring where you left off…"
        case .brainCapture, .screen:
            return "Restoring your workspace…"
        }
    }

    private static func estimatedRestartSeconds(for context: WorkingContext) -> Int {
        switch context.kind {
        case .browser, .document, .file: return 1
        case .aiCoach: return 1
        case .note: return 1
        default: return 1
        }
    }
}
