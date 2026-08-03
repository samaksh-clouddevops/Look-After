import Foundation
import LookAfterCore

/// Produces structured decisions from reasoning + existing rule engines.
/// Wraps ContextBriefingGenerator — does not replace it yet, but owns the output shape.
public struct DecisionEngine: Sendable {
    private let briefingGenerator: ContextBriefingGenerator
    private let intentBuilder: IntentBuilder
    private let simulationEngine: SimulationEngine
    private let calendar: Calendar

    public init(
        briefingGenerator: ContextBriefingGenerator = ContextBriefingGenerator(),
        intentBuilder: IntentBuilder = IntentBuilder(),
        simulationEngine: SimulationEngine = SimulationEngine(),
        calendar: Calendar = .current
    ) {
        self.briefingGenerator = briefingGenerator
        self.intentBuilder = intentBuilder
        self.simulationEngine = simulationEngine
        self.calendar = calendar
    }

    public func decide(
        world: WorldState,
        reasoning: ReasoningTrace,
        input: BrainTickInput
    ) -> (decision: BrainDecision, briefing: ContextBriefing) {
        let briefing = briefingGenerator.generate(
            from: input.snapshot,
            resume: input.resume,
            userName: input.userName,
            now: input.now,
            peakStartHour: input.peakStartHour,
            context: ContextBriefingGenerator.GenerationContext(
                upcomingBills: input.upcomingBills,
                timelineItems: input.timelineItems,
                isWeekend: input.isWeekend,
                tasks: input.tasks,
                healthSummary: input.healthSummary,
                completedTaskIDs: input.completedTaskIDs,
                flowConfidenceScore: input.flowConfidenceScore
            )
        )

        let hero = briefing.hero
        let heroTask = resolveHeroTask(hero: hero, tasks: input.tasks, world: world)
        var semantics = SemanticDecisionBuilder.from(hero: hero, task: heroTask)
        semantics.confidence = hero.confidenceScore
        semantics.estimateMinutes = hero.durationEstimate.pointMinutes

        let rendered = HumanLanguage.render(semantics, snapshot: input.snapshot, whyNow: hero.whyNowReasons)

        // Sanitize — reject unsafe medication copy if it leaked through
        var headline = UserFacingCopy.sanitize(rendered.headline)
        var whyNow = hero.whyNowReasons
        if !MedicationReasoningEngine.isSafeRecommendation(headline, status: world.medicationStatus) {
            headline = UserFacingCopy.sanitize(rendered.buttonLabel)
        }
        for reason in whyNow where !MedicationReasoningEngine.isSafeRecommendation(reason, status: world.medicationStatus) {
            whyNow = whyNow.filter { MedicationReasoningEngine.isSafeRecommendation($0, status: world.medicationStatus) }
        }

        // Inject schedule-bound medication reminder into reasoning if due
        if let medMessage = MedicationReasoningEngine.reminderMessage(for: world.medicationStatus),
           !whyNow.contains(medMessage) {
            whyNow.insert(medMessage, at: 0)
        }

        let alternatives = buildAlternatives(world: world, hero: hero)

        let expectedOutcome = hero.outcomeLine.isEmpty ? expectedOutcome(from: reasoning) : hero.outcomeLine

        let intent = intentBuilder.build(
            world: world,
            reasoning: reasoning,
            semantics: semantics,
            heroTask: heroTask,
            expectedOutcome: expectedOutcome,
            confidence: hero.confidenceScore
        )

        let simulations = simulationEngine.simulate(
            chosen: intent,
            world: world,
            reasoning: reasoning,
            alternatives: alternatives,
            heroTask: heroTask
        )

        let decision = BrainDecision(
            intent: intent,
            simulations: simulations,
            semantics: semantics,
            primaryAction: hero.action,
            headline: headline,
            supportingLine: rendered.durationLine,
            whyNow: whyNow,
            confidence: hero.confidenceScore,
            confidenceLevel: hero.confidenceLevel,
            expectedOutcome: expectedOutcome,
            alternatives: alternatives,
            reasoning: reasoning,
            durationEstimate: hero.durationEstimate,
            insights: hero.insights
        )

        return (decision, briefing)
    }

    private func buildAlternatives(world: WorldState, hero: HeroBriefing) -> [BrainAlternative] {
        var alts: [BrainAlternative] = []

        if hero.action.kind != .viewPlan {
            alts.append(BrainAlternative(
                label: "Map out your day",
                action: ContextAction(label: "View plan", kind: .viewPlan),
                reason: "See the full picture before committing"
            ))
        }

        if world.cognitiveLoad == .overloaded || (world.sleepHoursLastNight ?? 8) < 6 {
            let schedContext = TaskSemanticScheduler.Context(
                now: world.generatedAt,
                energyScore: world.currentEnergy,
                sleepHours: world.sleepHoursLastNight,
                freeBlockMinutes: world.availableMinutes,
                calendar: calendar
            )
            if let light = world.topTasks.first(where: { task in
                guard task.id != hero.action.taskID else { return false }
                let profile = task.resolvedSemanticProfile
                guard profile.energyRequirement == .minimal || profile.energyRequirement == .low else { return false }
                return TaskSemanticScheduler.schedulability(profile: profile, context: schedContext).isAllowed
            }) {
                alts.append(BrainAlternative(
                    label: light.title,
                    action: ContextAction(label: light.title, taskID: light.id, kind: .beginWork),
                    reason: "Lighter option while energy is low"
                ))
            }
        }

        return alts
    }

    private func expectedOutcome(from reasoning: ReasoningTrace) -> String {
        reasoning.conclusions.first ?? "You'll make meaningful progress without overcommitting."
    }

    private func resolveHeroTask(hero: HeroBriefing, tasks: [LifeTask], world: WorldState) -> LifeTask? {
        let schedContext = TaskSemanticScheduler.Context(
            now: world.generatedAt,
            energyScore: world.currentEnergy,
            sleepHours: world.sleepHoursLastNight,
            freeBlockMinutes: world.availableMinutes,
            calendar: calendar
        )

        if let taskID = hero.action.taskID,
           let task = tasks.first(where: { $0.id == taskID }) {
            let profile = task.resolvedSemanticProfile
            if TaskSemanticScheduler.schedulability(profile: profile, context: schedContext).isAllowed {
                return task
            }
            if profile.semanticType == .medication {
                return nil
            }
            return task
        }

        if let mission = world.currentMission {
            let profile = mission.resolvedSemanticProfile
            if TaskSemanticScheduler.schedulability(profile: profile, context: schedContext).isAllowed {
                return mission
            }
        }

        return tasks.first { task in
            TaskSemanticScheduler.schedulability(
                profile: task.resolvedSemanticProfile,
                context: schedContext
            ).isAllowed
        } ?? world.currentMission
    }
}
