import Foundation

/// Resolves WHAT the user is accomplishing — never HOW the system executes it.
public enum HeroObjectiveResolver {

    /// Full user-facing headline with verb prefix (e.g. "Finish connecting Apple Health").
    public static func resolveHeadline(from context: HeroObjectiveContext) -> String {
        let raw = resolveRawObjective(from: context)
        guard !raw.isEmpty else {
            return HumanLanguage.render(.pickUp).headline
        }

        if let task = context.task {
            var decision = SemanticDecisionBuilder.from(task: task, snapshot: context.snapshot)
            decision.object = DecisionObject(
                kind: decision.object.kind,
                rawTitle: raw,
                taskID: task.id
            )
            decision.progress = context.progress
            if context.estimatedRemainingMinutes > 0 {
                decision.estimateMinutes = context.estimatedRemainingMinutes
            }
            let rendered = HumanLanguage.render(decision, snapshot: context.snapshot)
            return UserFacingCopy.ensurePublicObjective(rendered.headline, rawObjective: raw, context: context)
        }

        let headline = HumanLanguage.outcomeHeadline(title: raw, progress: context.progress)
        return UserFacingCopy.ensurePublicObjective(headline, rawObjective: raw, context: context)
    }

    /// Objective noun phrase only — no execution-mechanism labels.
    public static func resolveRawObjective(from context: HeroObjectiveContext) -> String {
        for candidate in candidateObjectives(from: context) {
            let cleaned = normalize(candidate)
            if !cleaned.isEmpty, !UserFacingCopy.isInternalExecutionLabel(cleaned) {
                return cleaned
            }
        }
        return inferFallback(from: context)
    }

    // MARK: - Candidates

    private static func candidateObjectives(from context: HeroObjectiveContext) -> [String] {
        var candidates: [String] = []

        if let task = context.task {
            candidates.append(contentsOf: taskObjectives(task))
        }

        if let desired = context.desiredOutcome { candidates.append(desired) }
        if let notes = context.relatedNotes { candidates.append(notes) }
        if let note = context.resumeNote { candidates.append(note) }
        if let previous = context.previousSessionTitle { candidates.append(previous) }
        if let mission = context.mission { candidates.append(mission) }
        if let project = context.project { candidates.append(project) }

        return candidates
    }

    private static func taskObjectives(_ task: LifeTask) -> [String] {
        var list: [String] = []
        let profile = task.resolvedSemanticProfile

        if !task.description.isEmpty { list.append(task.description) }

        if profile.semanticType != .medication {
            let nextStep = task.steps.first(where: { !$0.isCompleted })?.title
            if let nextStep, !nextStep.isEmpty, !isLocationPrepStep(nextStep) {
                list.append(nextStep)
            }
        }

        if !profile.subtype.isEmpty, !isGenericSubtype(profile.subtype) {
            list.append(profile.subtype)
        }

        if let note = task.aiReasoningNote, !note.isEmpty { list.append(note) }
        if !task.notes.isEmpty { list.append(task.notes) }

        for tag in task.tags where !tag.isEmpty {
            list.append(tag)
        }

        if task.lifeArea == .relationships {
            list.append(inferCommunicationObjective(task))
        }

        list.append(task.title)

        return list
    }

    private static func isLocationPrepStep(_ step: String) -> Bool {
        let lower = step.lowercased()
        let markers = [
            "walk to", "go to", "find ", "where ", "is kept", "head to",
            "get to", "locate ", "pick up from"
        ]
        return markers.contains { lower.contains($0) }
    }

    // MARK: - Fallback inference

    private static func inferFallback(from context: HeroObjectiveContext) -> String {
        if let task = context.task {
            if task.lifeArea == .finance {
                return inferFinanceObjective(task)
            }
            if task.lifeArea == .relationships || task.lifeArea == .work {
                return inferCommunicationObjective(task)
            }
            if task.lifeArea == .health {
                return "Connect Apple Health"
            }
        }

        if context.progress > 0 {
            return "Pick up where you left off"
        }

        return ""
    }

    private static func inferFinanceObjective(_ task: LifeTask) -> String {
        let lower = task.title.lowercased()
        if lower.contains("bill") || lower.contains("pay") {
            return task.title
        }
        return "Pay \(task.title)"
    }

    private static func inferCommunicationObjective(_ task: LifeTask) -> String {
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = title.lowercased()
        if lower.hasPrefix("reply to ") || lower.hasPrefix("email ") || lower.hasPrefix("text ") {
            return title
        }
        if lower.hasPrefix("call ") { return title }
        return "Reply to \(title)"
    }

    private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isGenericSubtype(_ subtype: String) -> Bool {
        let lower = subtype.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower == "general task" || lower == "general" || lower == "task"
    }
}
