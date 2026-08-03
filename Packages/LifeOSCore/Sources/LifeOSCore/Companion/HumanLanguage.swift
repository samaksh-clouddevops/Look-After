import Foundation

/// Layer 2 — deterministic natural language from structured semantics. No LLM.
public enum HumanLanguage {
    // MARK: - Render pipeline (semantics → UI copy)

    public static func render(
        _ decision: SemanticDecision,
        snapshot: LifeContextSnapshot? = nil,
        whyNow: [String] = []
    ) -> RenderedDecision {
        let headline = headline(for: decision)
        let benefitLine = benefitLine(
            for: decision.benefit,
            snapshot: snapshot,
            whyNow: whyNow
        )
        let durationLine = durationLabel(minutes: decision.estimateMinutes)
            .replacingOccurrences(of: " left", with: "")

        return RenderedDecision(
            headline: headline,
            benefitLine: benefitLine,
            durationLine: durationLine,
            buttonLabel: actionButtonLabel(
                headline: headline,
                objectKind: decision.object.kind,
                isContinue: decision.progress > 0,
                isPreparation: false
            )
        )
    }

    /// Distinct action label — never duplicates the headline.
    public static func actionButtonLabel(
        headline: String,
        objectKind: DecisionObjectKind,
        isContinue: Bool = false,
        isPreparation: Bool = false
    ) -> String {
        if isPreparation { return "I'm ready" }

        switch objectKind {
        case .medication:
            return "Log it"
        case .capture:
            return "Remember this"
        case .dayPlan:
            return "View plan"
        case .shopping:
            return isContinue ? "Continue" : "Start now"
        default:
            break
        }

        if isContinue { return "Continue" }

        let lower = headline.lowercased()
        if lower.hasPrefix("open ") || lower.hasPrefix("review agenda") { return "I'm ready" }
        if lower.contains("put on") || lower.contains("fill your") { return "I'm ready" }
        if lower.hasPrefix("plan ") { return "Start now" }

        return "Start now"
    }

    public static func recommendationSummary(
        from decision: SemanticDecision,
        snapshot: LifeContextSnapshot? = nil,
        whyNow: [String] = []
    ) -> String {
        let rendered = render(decision, snapshot: snapshot, whyNow: whyNow)
        return [rendered.headline, rendered.benefitLine, rendered.durationLine]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    // MARK: - Primary actions

    public static func outcomeHeadline(context: HeroObjectiveContext) -> String {
        HeroObjectiveResolver.resolveHeadline(from: context)
    }

    public static func outcomeHeadline(task: LifeTask?, context: HeroObjectiveContext? = nil) -> String {
        guard let task else { return render(.pickUp).headline }
        let ctx = context ?? HeroObjectiveContextBuilder.from(task: task)
        return HeroObjectiveResolver.resolveHeadline(from: ctx)
    }

    public static func outcomeHeadline(title: String, progress: Double = 0) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return render(.pickUp).headline }
        if UserFacingCopy.isInternalExecutionLabel(trimmed) {
            return render(.pickUp).headline
        }
        return render(SemanticDecisionBuilder.from(title: trimmed, progress: progress)).headline
    }

    public static func resumeHeadline(title: String) -> String {
        let outcome = outcomeHeadline(title: title)
        if outcome.hasPrefix("Finish") || outcome.hasPrefix("Fix") || outcome.hasPrefix("Wrap") || outcome.hasPrefix("Keep") {
            return outcome
        }
        return "Keep going on \(soften(title))"
    }

    public static func durationLabel(minutes: Int, rangeMin: Int? = nil, rangeMax: Int? = nil, uncertain: Bool = false) -> String {
        if uncertain, let lo = rangeMin, let hi = rangeMax, lo != hi {
            return "About \(lo)–\(hi) minutes left"
        }
        if minutes >= 120 {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 { return "About \(hours) hours left" }
            return "About \(hours) h \(mins) min left"
        }
        return "About \(minutes) minutes left"
    }

    // MARK: - Life impact (Why now)

    public static func meetingContext(minutes: Int, event: String) -> String {
        "You still have \(minutes) minutes before \(event)."
    }

    public static func priorityImpact(task: LifeTask, snapshot: LifeContextSnapshot) -> String {
        if let event = snapshot.calendarAvailability.nextEventTitle,
           let mins = snapshot.calendarAvailability.minutesUntilNextEvent,
           mins > 15, mins <= 180 {
            return "Finish this and you'll have nothing important left before \(event)."
        }
        if task.isOverdue {
            return "Clearing this lifts a weight you've been carrying."
        }
        return "Finish this and the rest of your morning stays open."
    }

    public static func deadlineImpact(deadline: Date, snapshot: LifeContextSnapshot, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: Date()),
            to: calendar.startOfDay(for: deadline)
        ).day ?? 0

        switch days {
        case ..<0:
            return "Clearing this lifts a weight you've been carrying."
        case 0:
            if let event = snapshot.calendarAvailability.nextEventTitle,
               let mins = snapshot.calendarAvailability.minutesUntilNextEvent, mins > 30 {
                return "Finish this now and you'll have nothing important left before \(event)."
            }
            return "Finish this and the rest of today feels lighter."
        case 1:
            let hour = Calendar.current.component(.hour, from: Date())
            if hour < 12 {
                return "If you finish this now, the rest of your morning stays free."
            }
            return "If you finish this now, your afternoon stays free."
        default:
            return "A little progress now means less rush later."
        }
    }

    public static func freeTimeImpact(minutes: Int) -> String {
        "You have a quiet stretch — about \(minutes) minutes."
    }

    public static func progressImpact(fraction: Double) -> String {
        "You're already \(Int(fraction * 100))% there — momentum helps."
    }

    public static func focusModeImpact() -> String {
        "Your phone is quiet right now — good time to focus."
    }

    public static func poorSleepImpact(waitUntil: String?) -> String {
        if let waitUntil {
            return "Last night was rough — save the hard stuff until after \(waitUntil)."
        }
        return "Last night was rough — go easy on yourself."
    }

    public static func defaultWhyNow() -> String {
        "This is the gentlest useful next step."
    }

    public static func continueContextImpact(elapsedHours: Double, snapshot: LifeContextSnapshot) -> String {
        var lines: [String] = []
        if elapsedHours < 1 {
            lines.append("You just stepped away — easy to slip back in.")
        } else if elapsedHours < 8 {
            lines.append("You were on this earlier today.")
        } else {
            lines.append("This is where you left off.")
        }
        if let mins = snapshot.calendarAvailability.minutesUntilNextEvent, mins > 0, mins <= 120 {
            lines.append("You still have \(mins) minutes before your next thing.")
        }
        return lines.first ?? "This is where you left off."
    }

    // MARK: - Restoration steps

    public static func restorationSteps(
        for context: WorkingContext,
        resume: ResumeSnapshot?,
        snapshot: LifeContextSnapshot? = nil,
        task: LifeTask? = nil
    ) -> [String] {
        var steps: [String] = []

        if snapshot?.calendarAvailability.nextEventTitle != nil {
            steps.append("Calendar")
        }
        if resume?.lastNote != nil || context.kind == .note || context.kind == .brainCapture {
            steps.append("Notes")
        }
        if resume?.lastBrowserLink != nil || context.kind == .browser {
            steps.append("Safari")
        }
        if resume?.lastDocument != nil || context.kind == .document || context.kind == .file {
            steps.append("Document")
        }
        if resume?.lastAIConversationPreview != nil || context.kind == .aiCoach {
            steps.append("Conversation")
        }

        let taskTitle = (task?.title ?? context.title).lowercased()
        if taskTitle.contains("healthkit") || taskTitle.contains("health kit") {
            steps.append("HealthKit Import")
        }

        let label = context.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty, !steps.contains(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) {
            let short = label.count > 28 ? String(label.prefix(28)) + "…" : label
            if !steps.contains(short) {
                steps.append(short)
            }
        }

        if steps.isEmpty { return ["Workspace"] }
        return steps
    }

    public static func homeLoadingSteps() -> [String] {
        ["Your calendar", "Last night", "What matters"]
    }

    // MARK: - Semantic templates

    private static func headline(for decision: SemanticDecision) -> String {
        if decision.object.rawTitle == "Pick up where you left off" {
            return "Pick up where you left off"
        }

        switch decision.object.kind {
        case .appleHealthIntegration:
            switch decision.verb {
            case .continue, .wrapUp: return "Continue connecting Apple Health"
            default: return "Finish connecting Apple Health"
            }
        case .oauthSignIn:
            return "Finish signing people in safely"
        case .searchPerformance:
            return "Finish making search faster"
        case .shopping:
            return decision.verb == .shop ? "Finish the shopping" : "Finish the shopping"
        case .dayPlan:
            return "Map out your day"
        case .capture:
            return "Remember this"
        case .startWork:
            switch decision.verb {
            case .continue, .wrapUp: return "Continue Working"
            default: return "Start Work"
            }
        case .medication:
            if decision.object.rawTitle.isEmpty { return "Take your medication" }
            let title = decision.object.rawTitle
            let lower = title.lowercased()
            if lower.hasPrefix("take ") || lower.hasPrefix("log ") { return title }
            return "Take \(title)"
        case .deepWork:
            switch decision.verb {
            case .continue, .wrapUp: return "Continue \(decision.object.rawTitle)"
            default: return decision.object.rawTitle
            }
        case .exercise:
            return decision.object.rawTitle
        case .errand:
            return decision.object.rawTitle
        case .genericTask:
            return headlineForGeneric(decision)
        }
    }

    private static func headlineForGeneric(_ decision: SemanticDecision) -> String {
        let trimmed = decision.object.rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return render(.pickUp).headline }

        let lower = trimmed.lowercased()

        if decision.progress > 0 {
            if lower == "start work" || lower == "work" { return "Continue Working" }
            if decision.progress >= 0.5 {
                let wrap = "Wrap up \(trimmed)"
                if !isAwkwardLabel(wrap) { return wrap }
            }
            let continued = "Continue \(trimmed)"
            if !isAwkwardLabel(continued) { return continued }
            return trimmed
        }

        if shouldPreserveTitle(trimmed) { return trimmed }

        switch decision.verb {
        case .fix:
            if lower.hasPrefix("fix ") {
                return "Fix \(soften(String(trimmed.dropFirst(4))))"
            }
            return "Fix \(soften(trimmed))"
        case .wrapUp:
            return "Wrap up \(trimmed)"
        case .continue:
            return isAwkwardLabel("Continue \(trimmed)") ? trimmed : "Continue \(trimmed)"
        case .start:
            return trimmed
        case .finish:
            if lower.hasPrefix("implement ") {
                let candidate = "Finish setting up \(soften(String(trimmed.dropFirst(10))))"
                return isAwkwardLabel(candidate) ? trimmed : candidate
            }
            if lower.hasPrefix("review ") {
                let candidate = "Finish reviewing \(soften(String(trimmed.dropFirst(7))))"
                return isAwkwardLabel(candidate) ? trimmed : candidate
            }
            if lower.hasPrefix("build ") {
                let candidate = "Finish building \(soften(String(trimmed.dropFirst(6))))"
                return isAwkwardLabel(candidate) ? trimmed : candidate
            }
            if lower.contains("deploy") { return "Finish getting this live" }
            let candidate = "Finish \(trimmed)"
            return isAwkwardLabel(candidate) ? trimmed : candidate
        default:
            let candidate = "Finish \(trimmed)"
            return isAwkwardLabel(candidate) ? trimmed : candidate
        }
    }

    private static func benefitLine(
        for benefit: DecisionBenefit,
        snapshot: LifeContextSnapshot?,
        whyNow: [String]
    ) -> String {
        if let first = whyNow.first, !first.isEmpty { return first }

        switch benefit {
        case .unlockHealthInsights:
            return "This unlocks your health dashboard."
        case .unlockSleepInsights:
            return "This unlocks sleep and recovery insights."
        case .clearBiggestBlocker:
            return "This removes today's biggest blocker."
        case .freeTimeBeforeEvent(let event):
            return "Finish this and you'll have nothing important left before \(event)."
        case .reduceOverdueWeight:
            return "Clearing this lifts a weight you've been carrying."
        case .maintainMomentum:
            return "You're already partway there — momentum helps."
        case .openMorning:
            return "Finish this and the rest of your morning stays open."
        case .openAfternoon:
            return "If you finish this now, your afternoon stays free."
        case .lighterDay:
            return "Finish this and the rest of today feels lighter."
        case .none:
            return defaultWhyNow()
        }
    }

    // MARK: - Helpers

    private static func shouldPreserveTitle(_ title: String) -> Bool {
        let lower = title.lowercased()
        let preserve = [
            "start work", "continue working", "get started",
            "write", "read", "review", "plan", "work"
        ]
        if preserve.contains(lower) { return true }
        let words = title.split(separator: " ")
        return words.count <= 3
            && !lower.contains("implement")
            && !lower.contains("api")
            && !lower.contains("healthkit")
    }

    private static func isAwkwardLabel(_ label: String) -> Bool {
        let lower = label.lowercased()
        let awkward = [
            "finish start", "finish continue", "finish finish",
            "finish work", "finish get", "keep going on start"
        ]
        return awkward.contains(where: { lower.contains($0) })
            || UserFacingCopy.isInternalExecutionLabel(label)
    }

    private static func soften(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "API", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Integration", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Implementation", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
