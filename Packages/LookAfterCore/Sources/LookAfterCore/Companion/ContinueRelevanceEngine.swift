import Foundation

public enum ContinueRelevanceDecision: Sendable, Equatable {
    case continueWork(WorkingContext, reasons: [String])
    case freshStart(reason: String)
    case askUser(prompt: String, options: [String])
}

/// Decides whether "Continue where you left off" is still the best action.
public struct ContinueRelevanceEngine: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public struct Input: Sendable {
        public var resume: ResumeSnapshot?
        public var snapshot: LifeContextSnapshot
        public var heroTask: LifeTask?
        public var completedTaskIDs: Set<String>
        public var now: Date

        public init(
            resume: ResumeSnapshot?,
            snapshot: LifeContextSnapshot,
            heroTask: LifeTask?,
            completedTaskIDs: Set<String> = [],
            now: Date = Date()
        ) {
            self.resume = resume
            self.snapshot = snapshot
            self.heroTask = heroTask
            self.completedTaskIDs = completedTaskIDs
            self.now = now
        }
    }

    public func evaluate(_ input: Input) -> ContinueRelevanceDecision {
        guard let resume = input.resume, !resume.isStale else {
            return .freshStart(reason: "No recent working context")
        }

        let context = resume.workingContext ?? inferredContext(from: resume)
        guard let working = context else {
            return .freshStart(reason: "Nothing to restore")
        }

        if let taskID = working.taskID ?? resume.lastTaskID,
           input.completedTaskIDs.contains(taskID) {
            return .freshStart(reason: "You already finished this elsewhere")
        }

        if isNewDayMorning(resume: resume, now: input.now),
           !wasInterruptedRecently(resume: resume, now: input.now) {
            return .freshStart(reason: "New day — today's priorities may have changed")
        }

        if let hero = input.heroTask,
           let resumeTaskID = working.taskID ?? resume.lastTaskID,
           hero.id != resumeTaskID,
           isUrgentOverride(hero: hero, resume: resume, snapshot: input.snapshot) {
            return .freshStart(reason: "Something more time-sensitive came up")
        }

        if input.snapshot.sleepQuality == .poor || input.snapshot.sleepQuality == .fair,
           isNewDayMorning(resume: resume, now: input.now),
           working.kind == .focusSession || working.kind == .task {
            if let hero = input.heroTask, hero.title != working.title {
                return .freshStart(reason: "After a rough night, a gentler start may help")
            }
        }

        if !wasInterruptedRecently(resume: resume, now: input.now),
           hoursSince(resume.savedAt, now: input.now) > 12 {
            return .askUser(
                prompt: "I'm not sure what would help most right now.",
                options: ["Continue yesterday's work", "Plan today together"]
            )
        }

        let reasons = continueReasons(resume: resume, snapshot: input.snapshot)
        return .continueWork(working, reasons: reasons)
    }

    public func shouldOfferContinue(_ input: Input) -> Bool {
        switch evaluate(input) {
        case .continueWork: return true
        case .askUser: return true
        case .freshStart: return false
        }
    }

    private func inferredContext(from resume: ResumeSnapshot) -> WorkingContext? {
        if let ctx = resume.workingContext { return ctx }
        if let title = resume.lastTaskTitle {
            return WorkingContext(kind: .task, title: title, taskID: resume.lastTaskID)
        }
        if let note = resume.lastNote {
            return WorkingContext(kind: .note, title: note)
        }
        if let doc = resume.lastDocument {
            return WorkingContext(kind: .document, title: doc)
        }
        if let link = resume.lastBrowserLink {
            return WorkingContext(kind: .browser, title: link)
        }
        if let preview = resume.lastAIConversationPreview {
            return WorkingContext(kind: .aiCoach, title: preview)
        }
        return nil
    }

    private func wasInterruptedRecently(resume: ResumeSnapshot, now: Date) -> Bool {
        hoursSince(resume.savedAt, now: now) <= 8
    }

    private func isNewDayMorning(resume: ResumeSnapshot, now: Date) -> Bool {
        !calendar.isDate(resume.savedAt, inSameDayAs: now) && calendar.component(.hour, from: now) < 12
    }

    private func hoursSince(_ date: Date, now: Date) -> Double {
        now.timeIntervalSince(date) / 3600
    }

    private func isUrgentOverride(hero: LifeTask, resume: ResumeSnapshot, snapshot: LifeContextSnapshot) -> Bool {
        if hero.isOverdue { return true }
        if let deadline = hero.deadline {
            let hours = deadline.timeIntervalSince(Date()) / 3600
            if hours >= 0, hours <= 4 { return true }
        }
        if let event = snapshot.calendarAvailability.nextEventTitle,
           let mins = snapshot.calendarAvailability.minutesUntilNextEvent,
           mins <= 90,
           hero.title.localizedCaseInsensitiveContains(event) || event.localizedCaseInsensitiveContains(hero.title) {
            return true
        }
        _ = resume
        return false
    }

    private func continueReasons(resume: ResumeSnapshot, snapshot: LifeContextSnapshot) -> [String] {
        let elapsed = hoursSince(resume.savedAt, now: Date())
        return [HumanLanguage.continueContextImpact(elapsedHours: elapsed, snapshot: snapshot)]
    }
}
