import Foundation

/// Continuous day-supervisor helpers (Capture / Decide / create / Focus / notifs).
public enum DaySupervisorContinuity {

    public enum CaptureFit: String, Sendable, Equatable {
        case fitToday
        case park
        case someday

        public var chipLabel: String {
            switch self {
            case .fitToday: return "Fits today"
            case .park: return "Park for a gap"
            case .someday: return "Someday"
            }
        }
    }

    /// Whether a captured/created duration fits remaining flex capacity.
    public static func captureFit(
        estimatedMinutes: Int,
        remainingFlexMinutes: Int
    ) -> CaptureFit {
        let minutes = max(estimatedMinutes, TaskDurationPolicy.minimumMinutes)
        if minutes <= remainingFlexMinutes { return .fitToday }
        if minutes <= remainingFlexMinutes + 45 { return .park }
        return .someday
    }

    /// Warning when creating a task that blows the remaining day.
    public static func createDurationWarning(
        estimatedMinutes: Int,
        remainingFlexMinutes: Int
    ) -> String? {
        let minutes = max(estimatedMinutes, TaskDurationPolicy.minimumMinutes)
        guard minutes > remainingFlexMinutes + 15 else { return nil }
        let over = minutes - remainingFlexMinutes
        return "This is ~\(over)m over what’s left today. Keep, shrink, or park?"
    }

    /// Feasible Decide-for-me pool: active, movable or due soon, duration fits open window.
    public static func feasibleTasks(
        from tasks: [LifeTask],
        openWindowMinutes: Int,
        energyPercent: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [LifeTask] {
        let day = calendar.startOfDay(for: now)
        let budget = max(openWindowMinutes, TaskDurationPolicy.minimumMinutes)
        return tasks.filter { task in
            guard task.status.isActive else { return false }
            if TaskRecurrenceEngine.isRecurrenceTemplate(task) { return false }
            let minutes = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
            if minutes > budget + 10 { return false }
            if energyPercent < 35, minutes > 40 { return false }
            if let date = task.scheduledDate, !calendar.isDate(date, inSameDayAs: day) {
                return false
            }
            return true
        }
    }

    /// One lean notification line from an audit (fault or next pull).
    public static func leanNotificationBody(from audit: DayAuditResult) -> String? {
        if let fault = audit.faults.first(where: { $0.severity == .high }) ?? audit.faults.first {
            return fault.message
        }
        if let pull = audit.possiblePulls.first {
            return "Gap open — pull “\(pull.title)”?"
        }
        return nil
    }

    /// Focus mid-session question when circuit breaker fires.
    public static func focusMismatchQuestion(kind: String) -> DayAuditQuestion {
        switch kind {
        case "hyperfocusBreak":
            return DayAuditQuestion(
                prompt: "You’ve been deep in this a while. What next?",
                options: ["Keep going", "Shrink the block", "Stop for now"]
            )
        default:
            return DayAuditQuestion(
                prompt: "This feels heavy for right now. What helps?",
                options: ["Switch task", "Shrink", "Stop"]
            )
        }
    }
}

/// Weekly → next-morning priors for DayAudit (UserDefaults-backed).
public enum DaySupervisorPriorsStore {
    private static let key = "daySupervisor.weeklyPriors"

    public struct Priors: Codable, Sendable, Equatable {
        public var preferLighterMornings: Bool
        public var deferDeepWorkAfterHour: Int?
        public var note: String
        public var updatedAt: Date

        public init(
            preferLighterMornings: Bool = false,
            deferDeepWorkAfterHour: Int? = nil,
            note: String = "",
            updatedAt: Date = Date()
        ) {
            self.preferLighterMornings = preferLighterMornings
            self.deferDeepWorkAfterHour = deferDeepWorkAfterHour
            self.note = note
            self.updatedAt = updatedAt
        }
    }

    public static func load() -> Priors? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let priors = try? JSONDecoder().decode(Priors.self, from: data) else {
            return nil
        }
        return priors
    }

    public static func save(_ priors: Priors) {
        guard let data = try? JSONEncoder().encode(priors) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    public static func ingest(retrospectiveHeadline: String, experiment: String?) {
        var priors = load() ?? Priors()
        let lower = (retrospectiveHeadline + " " + (experiment ?? "")).lowercased()
        if lower.contains("overwhelm") || lower.contains("too much") || lower.contains("overload") {
            priors.preferLighterMornings = true
        }
        if lower.contains("evening") && (lower.contains("deep") || lower.contains("focus")) {
            priors.deferDeepWorkAfterHour = 16
        }
        priors.note = String(retrospectiveHeadline.prefix(160))
        priors.updatedAt = Date()
        save(priors)
    }
}
