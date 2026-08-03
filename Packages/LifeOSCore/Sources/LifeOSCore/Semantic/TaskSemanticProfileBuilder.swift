import Foundation

/// Deterministic semantic understanding — no LLM. Safety baseline and offline fallback.
public enum TaskSemanticProfileBuilder {

    public static func build(from task: LifeTask) -> TaskSemanticProfile {
        let corpus = normalizedCorpus(for: task)

        if let medication = medicationProfile(task: task, corpus: corpus) {
            return medication
        }
        if let deepWork = deepWorkProfile(task: task, corpus: corpus) {
            return deepWork
        }
        if let errand = errandProfile(task: task, corpus: corpus) {
            return errand
        }
        if let exercise = exerciseProfile(task: task, corpus: corpus) {
            return exercise
        }
        if let communication = communicationProfile(task: task, corpus: corpus) {
            return communication
        }
        if let integration = integrationProfile(task: task, corpus: corpus) {
            return integration
        }

        return genericProfile(task: task)
    }

    /// Merge LLM output with deterministic safety rules. Medical constraints always win.
    public static func merge(llm: TaskSemanticProfile, deterministic: TaskSemanticProfile) -> TaskSemanticProfile {
        var merged = llm
        merged.source = .merged
        merged.confidence = min(max((llm.confidence + deterministic.confidence) / 2, 0.5), 1)

        if deterministic.semanticType == .medication || llm.semanticType == .medication {
            merged.semanticType = .medication
            merged.schedulingConstraints = unionConstraints(
                deterministic.schedulingConstraints,
                llm.schedulingConstraints
            )
            merged.forbiddenTimeWindows = unionWindows(
                deterministic.forbiddenTimeWindows,
                llm.forbiddenTimeWindows
            )
            merged.flexibility = minFlexibility(deterministic.flexibility, llm.flexibility)
            merged.consequenceOfDelay = maxConsequence(deterministic.consequenceOfDelay, llm.consequenceOfDelay)
            merged.splittable = false
            merged.interruptionTolerance = min(deterministic.interruptionTolerance, llm.interruptionTolerance)
            merged = enforceMedicationSafety(merged)
        }

        if merged.estimatedDuration <= 0 {
            merged.estimatedDuration = deterministic.estimatedDuration
        }

        return merged
    }

    // MARK: - Profiles

    private static func medicationProfile(task: LifeTask, corpus: String) -> TaskSemanticProfile? {
        let medicationTerms = [
            "levothyroxine", "thyroid", "synthroid", "medication", "medicine", "pill",
            "vitamin", "supplement", "prescription", "dose", "mg", "mcg"
        ]
        guard medicationTerms.contains(where: { corpus.contains($0) }) else { return nil }

        let isMorningThyroid = corpus.contains("levothyroxine")
            || corpus.contains("thyroid")
            || corpus.contains("synthroid")

        var constraints: [SchedulingConstraintKind] = [.sameTimeDaily]
        var preferred: [TimeWindowPreference] = [.morning]
        var forbidden: [TimeWindowPreference] = [.evening, .night]
        var subtype = "Daily medication"
        var required: [String] = ["Follow configured schedule"]

        if isMorningThyroid {
            subtype = "Morning fasting medication"
            constraints.append(contentsOf: [.beforeBreakfast, .requiresEmptyStomach, .neverEveningDose])
            required.append("Take before breakfast on empty stomach")
            forbidden = [.midday, .afternoon, .evening, .night]
        }

        return TaskSemanticProfile(
            semanticType: .medication,
            subtype: subtype,
            schedulingConstraints: constraints,
            requiredConditions: required,
            preferredTimeWindows: preferred,
            forbiddenTimeWindows: forbidden,
            estimatedDuration: min(task.estimatedMinutes, 5),
            flexibility: .rigid,
            splittable: false,
            interruptionTolerance: 0.1,
            energyRequirement: .minimal,
            cognitiveRequirement: .minimal,
            locationRequirement: "home",
            recurringRules: task.recurrenceRule == .none ? "Same time daily" : task.recurrenceRule.rawValue,
            consequenceOfDelay: .medicalRisk,
            confidence: isMorningThyroid ? 0.95 : 0.82,
            source: .deterministic
        )
    }

    private static func deepWorkProfile(task: LifeTask, corpus: String) -> TaskSemanticProfile? {
        let deepTerms = [
            "implement", "code", "coding", "oauth", "api", "architecture", "refactor",
            "debug", "design system", "search perf", "build feature"
        ]
        let errandTerms = ["shopping", "grocery", "groceries", "store", "pick up", "pharmacy", "errand"]
        if errandTerms.contains(where: { corpus.contains($0) }) { return nil }

        let termMatch = deepTerms.contains(where: { corpus.contains($0) })
        let looksDeep = termMatch
            || (task.difficulty == .hard && termMatch)
            || (task.estimatedMinutes >= 45 && termMatch)

        guard looksDeep else { return nil }

        let isCoding = corpus.contains("code") || corpus.contains("implement")
            || corpus.contains("oauth") || corpus.contains("api")

        return TaskSemanticProfile(
            semanticType: .deepWork,
            subtype: isCoding ? "Deep coding" : "Focused work block",
            schedulingConstraints: [.requiresUninterruptedBlock, .avoidAfterPoorSleep],
            requiredConditions: ["Uninterrupted focus block"],
            preferredTimeWindows: [.morning, .midday],
            forbiddenTimeWindows: [.night],
            estimatedDuration: max(task.estimatedMinutes, 45),
            flexibility: .low,
            splittable: task.estimatedMinutes >= 90,
            interruptionTolerance: 0.15,
            energyRequirement: task.requiredEnergy == .peak ? .peak : .high,
            cognitiveRequirement: .deepFocus,
            consequenceOfDelay: task.isOverdue ? .high : .moderate,
            confidence: 0.84,
            source: .deterministic
        )
    }

    private static func errandProfile(task: LifeTask, corpus: String) -> TaskSemanticProfile? {
        let errandTerms = ["shopping", "grocery", "groceries", "store", "pick up", "pickup", "pharmacy", "errand"]
        guard errandTerms.contains(where: { corpus.contains($0) }) else { return nil }

        return TaskSemanticProfile(
            semanticType: .errand,
            subtype: corpus.contains("grocery") || corpus.contains("shopping") ? "Shopping" : "Errand",
            schedulingConstraints: [.requiresStoreOpen, .combineWithNearbyErrands],
            requiredConditions: ["Store or location must be open"],
            preferredTimeWindows: [.midday, .afternoon],
            forbiddenTimeWindows: [.night],
            estimatedDuration: task.estimatedMinutes,
            flexibility: .high,
            splittable: true,
            interruptionTolerance: 0.7,
            energyRequirement: .low,
            cognitiveRequirement: .minimal,
            locationRequirement: "store",
            consequenceOfDelay: .low,
            confidence: 0.86,
            source: .deterministic
        )
    }

    private static func exerciseProfile(task: LifeTask, corpus: String) -> TaskSemanticProfile? {
        let exerciseTerms = ["gym", "workout", "exercise", "run", "jog", "walk", "yoga", "lift", "training"]
        guard exerciseTerms.contains(where: { corpus.contains($0) }) else { return nil }

        return TaskSemanticProfile(
            semanticType: .physicalActivity,
            subtype: "Exercise",
            schedulingConstraints: [.afterMealsForbidden],
            requiredConditions: ["Avoid immediately after large meals"],
            preferredTimeWindows: [.evening, .morning],
            forbiddenTimeWindows: [],
            estimatedDuration: max(task.estimatedMinutes, 30),
            flexibility: .moderate,
            splittable: false,
            interruptionTolerance: 0.35,
            energyRequirement: .moderate,
            cognitiveRequirement: .light,
            locationRequirement: corpus.contains("gym") ? "gym" : "outdoors",
            consequenceOfDelay: .low,
            confidence: 0.83,
            source: .deterministic
        )
    }

    private static func communicationProfile(task: LifeTask, corpus: String) -> TaskSemanticProfile? {
        let commTerms = ["email", "reply", "call", "message", "text", "follow up", "reach out"]
        guard commTerms.contains(where: { corpus.contains($0) }) else { return nil }

        return TaskSemanticProfile(
            semanticType: .communication,
            subtype: "Communication",
            schedulingConstraints: [],
            preferredTimeWindows: [.midday, .afternoon],
            estimatedDuration: min(task.estimatedMinutes, 20),
            flexibility: .high,
            splittable: true,
            interruptionTolerance: 0.8,
            energyRequirement: .low,
            cognitiveRequirement: .light,
            consequenceOfDelay: task.isOverdue ? .moderate : .low,
            confidence: 0.78,
            source: .deterministic
        )
    }

    private static func integrationProfile(task: LifeTask, corpus: String) -> TaskSemanticProfile? {
        if corpus.contains("healthkit") || corpus.contains("health kit") || corpus.contains("apple health") {
            return TaskSemanticProfile(
                semanticType: .administrative,
                subtype: "Health integration setup",
                schedulingConstraints: [.requiresUninterruptedBlock],
                preferredTimeWindows: [.morning, .midday],
                estimatedDuration: task.estimatedMinutes,
                flexibility: .moderate,
                energyRequirement: .moderate,
                cognitiveRequirement: .moderate,
                consequenceOfDelay: .moderate,
                confidence: 0.88,
                source: .deterministic
            )
        }
        return nil
    }

    private static func genericProfile(task: LifeTask) -> TaskSemanticProfile {
        TaskSemanticProfile(
            semanticType: .generic,
            subtype: "General task",
            estimatedDuration: task.estimatedMinutes,
            flexibility: .moderate,
            splittable: task.estimatedMinutes > 30,
            energyRequirement: energyFromTask(task),
            cognitiveRequirement: task.difficulty == .hard ? .moderate : .light,
            consequenceOfDelay: task.isOverdue ? .moderate : .low,
            confidence: 0.55,
            source: .deterministic
        )
    }

    // MARK: - Helpers

    private static func normalizedCorpus(for task: LifeTask) -> String {
        ([task.title, task.description] + task.tags + [task.notes])
            .joined(separator: " ")
            .lowercased()
    }

    private static func energyFromTask(_ task: LifeTask) -> SemanticEnergyRequirement {
        switch task.requiredEnergy {
        case .recovery, .low: return .low
        case .moderate: return .moderate
        case .high: return .high
        case .peak: return .peak
        }
    }

    private static func enforceMedicationSafety(_ profile: TaskSemanticProfile) -> TaskSemanticProfile {
        var safe = profile
        if !safe.schedulingConstraints.contains(.neverEveningDose) {
            safe.schedulingConstraints.append(.neverEveningDose)
        }
        safe.forbiddenTimeWindows = unionWindows(safe.forbiddenTimeWindows, [.evening, .night])
        safe.flexibility = .rigid
        safe.consequenceOfDelay = .medicalRisk
        return safe
    }

    private static func unionConstraints(
        _ lhs: [SchedulingConstraintKind],
        _ rhs: [SchedulingConstraintKind]
    ) -> [SchedulingConstraintKind] {
        Array(Set(lhs + rhs))
    }

    private static func unionWindows(
        _ lhs: [TimeWindowPreference],
        _ rhs: [TimeWindowPreference]
    ) -> [TimeWindowPreference] {
        Array(Set(lhs + rhs))
    }

    private static func minFlexibility(_ lhs: TaskFlexibility, _ rhs: TaskFlexibility) -> TaskFlexibility {
        let order: [TaskFlexibility] = [.rigid, .low, .moderate, .high]
        let li = order.firstIndex(of: lhs) ?? 0
        let ri = order.firstIndex(of: rhs) ?? 0
        return order[min(li, ri)]
    }

    private static func maxConsequence(_ lhs: ConsequenceOfDelay, _ rhs: ConsequenceOfDelay) -> ConsequenceOfDelay {
        let order: [ConsequenceOfDelay] = [.none, .low, .moderate, .high, .medicalRisk]
        let li = order.firstIndex(of: lhs) ?? 0
        let ri = order.firstIndex(of: rhs) ?? 0
        return order[max(li, ri)]
    }
}
