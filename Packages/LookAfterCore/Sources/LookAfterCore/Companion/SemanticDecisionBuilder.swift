import Foundation

/// Maps tasks and context into language-neutral semantics — no LLM, no English.
public enum SemanticDecisionBuilder {

    public static func from(
        title: String,
        progress: Double = 0,
        estimatedMinutes: Int = 20,
        taskID: String? = nil
    ) -> SemanticDecision {
        let object = classifyObject(title: title, taskID: taskID)
        let verb = resolveVerb(title: title, object: object, progress: progress)
        return SemanticDecision(
            verb: verb,
            object: object,
            estimateMinutes: estimatedMinutes,
            progress: progress
        )
    }

    public static func from(
        task: LifeTask,
        snapshot: LifeContextSnapshot? = nil,
        healthSummary: HealthSummary? = nil
    ) -> SemanticDecision {
        let profile = task.resolvedSemanticProfile
        let object = classifyObject(profile: profile, title: task.title, taskID: task.id)
        let verb = classifyVerb(task: task, object: object)
        let benefit = inferBenefit(
            task: task,
            profile: profile,
            object: object,
            snapshot: snapshot,
            healthSummary: healthSummary
        )

        return SemanticDecision(
            verb: verb,
            object: object,
            benefit: benefit,
            estimateMinutes: profile.estimatedDuration,
            confidence: max(task.completionProbability ?? 0, profile.confidence),
            progress: task.progress
        )
    }

    public static func from(hero: HeroBriefing, task: LifeTask?) -> SemanticDecision {
        if let task {
            var decision = from(task: task)
            decision.confidence = hero.confidenceScore
            decision.estimateMinutes = hero.durationEstimate.pointMinutes
            return decision
        }

        let title = hero.actionLine.isEmpty ? hero.buttonLabel : hero.actionLine
        let object = classifyObject(title: title, taskID: hero.action.taskID)
        return SemanticDecision(
            verb: verbFromActionKind(hero.action.kind),
            object: object,
            benefit: benefitFromOutcome(hero.outcomeLine),
            estimateMinutes: hero.durationEstimate.pointMinutes,
            confidence: hero.confidenceScore
        )
    }

    // MARK: - Classification

    private static func classifyObject(
        profile: TaskSemanticProfile,
        title: String,
        taskID: String?
    ) -> DecisionObject {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)

        switch profile.semanticType {
        case .medication:
            return DecisionObject(kind: .medication, rawTitle: trimmed, taskID: taskID)
        case .deepWork:
            return DecisionObject(kind: .deepWork, rawTitle: trimmed, taskID: taskID)
        case .physicalActivity:
            return DecisionObject(kind: .exercise, rawTitle: trimmed, taskID: taskID)
        case .errand:
            return DecisionObject(kind: profile.subtype.lowercased().contains("shop") ? .shopping : .errand, rawTitle: trimmed, taskID: taskID)
        case .administrative:
            return classifyObject(title: title, taskID: taskID)
        default:
            return classifyObject(title: title, taskID: taskID)
        }
    }

    private static func classifyObject(title: String, taskID: String?) -> DecisionObject {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if lower.contains("healthkit") || lower.contains("health kit") || lower.contains("apple health") {
            return DecisionObject(kind: .appleHealthIntegration, rawTitle: trimmed, taskID: taskID)
        }
        if lower.contains("oauth") || lower.contains("sign in") || lower.contains("sign-in") {
            return DecisionObject(kind: .oauthSignIn, rawTitle: trimmed, taskID: taskID)
        }
        if lower.contains("search") && (lower.contains("api") || lower.contains("perf") || lower.contains("speed")) {
            return DecisionObject(kind: .searchPerformance, rawTitle: trimmed, taskID: taskID)
        }
        if lower.contains("shopping") || lower.contains("grocery") {
            return DecisionObject(kind: .shopping, rawTitle: trimmed, taskID: taskID)
        }
        if lower == "start work" || lower == "work" || lower == "continue working" {
            return DecisionObject(kind: .startWork, rawTitle: trimmed, taskID: taskID)
        }

        return DecisionObject(kind: .genericTask, rawTitle: trimmed, taskID: taskID)
    }

    private static func classifyVerb(task: LifeTask, object: DecisionObject) -> DecisionVerb {
        resolveVerb(title: task.title, object: object, progress: task.progress)
    }

    private static func resolveVerb(title: String, object: DecisionObject, progress: Double) -> DecisionVerb {
        if progress > 0 {
            if object.kind == .startWork { return .continue }
            if progress >= 0.5 { return .wrapUp }
            return .continue
        }

        let lower = title.lowercased()
        if lower.hasPrefix("fix ") { return .fix }
        if lower.hasPrefix("review ") { return .finish }
        if object.kind == .shopping { return .shop }
        if object.kind == .appleHealthIntegration || object.kind == .oauthSignIn { return .finish }
        if object.kind == .startWork { return .start }
        return .finish
    }

    private static func verbFromActionKind(_ kind: ContextActionKind) -> DecisionVerb {
        switch kind {
        case .startTask, .beginWork: return .start
        case .continueTask, .resumeSession, .openContinueSession: return .continue
        case .openShopping: return .shop
        case .viewPlan: return .plan
        case .openCoach, .openBrain, .openHealthDetail, .startRecovery: return .start
        }
    }

    private static func inferBenefit(
        task: LifeTask,
        profile: TaskSemanticProfile,
        object: DecisionObject,
        snapshot: LifeContextSnapshot?,
        healthSummary: HealthSummary?
    ) -> DecisionBenefit {
        if profile.consequenceOfDelay == .medicalRisk {
            return .clearBiggestBlocker
        }

        switch object.kind {
        case .appleHealthIntegration:
            if healthSummary?.totalSleepMinutes == nil {
                return .unlockSleepInsights
            }
            return .unlockHealthInsights
        case .shopping:
            return .clearBiggestBlocker
        default:
            break
        }

        if task.isOverdue { return .reduceOverdueWeight }
        if task.progress > 0 { return .maintainMomentum }

        if let snapshot {
            if let event = snapshot.calendarAvailability.nextEventTitle,
               let mins = snapshot.calendarAvailability.minutesUntilNextEvent,
               mins > 15, mins <= 180 {
                return .freeTimeBeforeEvent(event)
            }
        }

        return .none
    }

    private static func benefitFromOutcome(_ outcome: String) -> DecisionBenefit {
        let lower = outcome.lowercased()
        if lower.contains("sleep") { return .unlockSleepInsights }
        if lower.contains("health") { return .unlockHealthInsights }
        if lower.contains("blocker") { return .clearBiggestBlocker }
        return .none
    }
}
