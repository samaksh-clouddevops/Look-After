import Foundation

/// Rich context for resolving ONE concrete user-facing objective — never an execution mechanism.
public struct HeroObjectiveContext: Sendable, Equatable {
    public var mission: String?
    public var project: String?
    public var task: LifeTask?
    public var progress: Double
    public var previousSessionTitle: String?
    public var previousSessionElapsedMinutes: Int
    public var relatedNotes: String?
    public var calendarEvent: String?
    public var minutesUntilNextEvent: Int?
    public var availableMinutes: Int?
    public var energyLevel: EnergyLevel?
    public var energyScore: Double?
    public var blockers: [String]
    public var estimatedRemainingMinutes: Int
    public var desiredOutcome: String?
    public var snapshot: LifeContextSnapshot?
    public var resumeNote: String?

    public init(
        mission: String? = nil,
        project: String? = nil,
        task: LifeTask? = nil,
        progress: Double = 0,
        previousSessionTitle: String? = nil,
        previousSessionElapsedMinutes: Int = 0,
        relatedNotes: String? = nil,
        calendarEvent: String? = nil,
        minutesUntilNextEvent: Int? = nil,
        availableMinutes: Int? = nil,
        energyLevel: EnergyLevel? = nil,
        energyScore: Double? = nil,
        blockers: [String] = [],
        estimatedRemainingMinutes: Int = 0,
        desiredOutcome: String? = nil,
        snapshot: LifeContextSnapshot? = nil,
        resumeNote: String? = nil
    ) {
        self.mission = mission
        self.project = project
        self.task = task
        self.progress = progress
        self.previousSessionTitle = previousSessionTitle
        self.previousSessionElapsedMinutes = previousSessionElapsedMinutes
        self.relatedNotes = relatedNotes
        self.calendarEvent = calendarEvent
        self.minutesUntilNextEvent = minutesUntilNextEvent
        self.availableMinutes = availableMinutes
        self.energyLevel = energyLevel
        self.energyScore = energyScore
        self.blockers = blockers
        self.estimatedRemainingMinutes = estimatedRemainingMinutes
        self.desiredOutcome = desiredOutcome
        self.snapshot = snapshot
        self.resumeNote = resumeNote
    }
}

/// Assembles hero objective context from Brain, task, and life signals.
public enum HeroObjectiveContextBuilder {

    public static func build(
        task: LifeTask?,
        snapshot: LifeContextSnapshot? = nil,
        resume: ResumeSnapshot? = nil,
        healthSummary: HealthSummary? = nil,
        workingContext: WorkingContext? = nil,
        blockers: [String] = []
    ) -> HeroObjectiveContext {
        let missionTask = task ?? snapshot?.currentMission
        let progress = missionTask?.progress ?? 0
        let priorMinutes = (resume?.lastTimerElapsedSeconds ?? 0) / 60
        let remaining = estimateRemainingMinutes(task: missionTask, priorMinutes: priorMinutes)

        var notes: [String] = []
        if let note = resume?.lastNote, !note.isEmpty { notes.append(note) }
        if let mission = missionTask?.notes, !mission.isEmpty { notes.append(mission) }
        if let reasoning = missionTask?.aiReasoningNote, !reasoning.isEmpty { notes.append(reasoning) }

        let project = missionTask?.tags.first(where: { !$0.isEmpty })
            ?? missionTask?.lifeArea.rawValue

        var desired: String?
        if let missionTask {
            let profile = missionTask.resolvedSemanticProfile
            if !profile.subtype.isEmpty { desired = profile.subtype }
        }

        return HeroObjectiveContext(
            mission: snapshot?.currentMission?.title,
            project: project,
            task: missionTask,
            progress: progress,
            previousSessionTitle: workingContext?.title ?? resume?.lastTaskTitle,
            previousSessionElapsedMinutes: priorMinutes,
            relatedNotes: notes.isEmpty ? nil : notes.joined(separator: " · "),
            calendarEvent: snapshot?.calendarAvailability.nextEventTitle,
            minutesUntilNextEvent: snapshot?.calendarAvailability.minutesUntilNextEvent,
            availableMinutes: snapshot?.availableTimeMinutes,
            energyLevel: nil,
            energyScore: snapshot.map { $0.currentEnergy },
            blockers: blockers,
            estimatedRemainingMinutes: remaining,
            desiredOutcome: desired,
            snapshot: snapshot,
            resumeNote: resume?.lastNote
        )
    }

    public static func from(task: LifeTask) -> HeroObjectiveContext {
        build(task: task)
    }

    private static func estimateRemainingMinutes(task: LifeTask?, priorMinutes: Int) -> Int {
        guard let task else { return 0 }
        let total = max(task.resolvedSemanticProfile.estimatedDuration, task.estimatedMinutes)
        if task.progress > 0, !task.steps.isEmpty {
            let remainingSteps = task.steps.filter { !$0.isCompleted }.count
            let perStep = max(total / max(task.steps.count, 1), TaskDurationPolicy.minimumMinutes)
            return max(remainingSteps * perStep, TaskDurationPolicy.minimumMinutes)
        }
        return max(total - priorMinutes, TaskDurationPolicy.minimumMinutes)
    }
}
