import Foundation

/// Whether a proposed clock makes sense for this task — type, time of day, duration, and neighbors.
/// Deterministic semantics first. Callers send `.needsAI` to the LLM judge.
public enum SemanticPlacementSense {

    public enum Verdict: Equatable, Sendable {
        case makesSense
        case doesNotMakeSense(String)
        case needsAI(String)
    }

    public struct Input: Sendable {
        public var task: LifeTask
        public var proposedStart: Date
        public var durationMinutes: Int
        public var occupied: [TaskScheduleInterval]
        public var neighborTasks: [LifeTask]
        public var calendar: Calendar
        public var dayEnd: Date?

        public init(
            task: LifeTask,
            proposedStart: Date,
            durationMinutes: Int,
            occupied: [TaskScheduleInterval] = [],
            neighborTasks: [LifeTask] = [],
            calendar: Calendar = .current,
            dayEnd: Date? = nil
        ) {
            self.task = task
            self.proposedStart = proposedStart
            self.durationMinutes = durationMinutes
            self.occupied = occupied
            self.neighborTasks = neighborTasks
            self.calendar = calendar
            self.dayEnd = dayEnd
        }
    }

    /// Search window from a bounding box, else preferred/forbidden semantic windows.
    public static func hourBounds(for task: LifeTask, calendar: Calendar = .current) -> PlanningSchedulePolicy.WorkHours? {
        if let box = TaskEphemeralityDefaults.boundingBox(for: task) {
            return SchedulePlacementGuard.workHours(forBox: box)
        }
        return hourBounds(from: task.resolvedSemanticProfile)
    }

    public static func hourBounds(from profile: TaskSemanticProfile) -> PlanningSchedulePolicy.WorkHours? {
        let preferred = Set(profile.preferredTimeWindows)
        let forbidden = Set(profile.forbiddenTimeWindows)
        if preferred.isEmpty || preferred == [.anytime], forbidden.isEmpty {
            return nil
        }

        var hours = Set<Int>()
        let windows: [TimeWindowPreference]
        if preferred.isEmpty || preferred.contains(.anytime) {
            windows = TimeWindowPreference.allCases.filter { $0 != .anytime && !forbidden.contains($0) }
        } else {
            windows = Array(preferred.subtracting(forbidden))
        }
        for window in windows {
            hours.formUnion(window.hours)
        }
        hours.subtract(forbidden.flatMap(\.hours))
        return workHours(from: hours)
    }

    public static func nearestPreferredStart(
        on day: Date,
        for task: LifeTask,
        calendar: Calendar = .current
    ) -> Date? {
        let profile = task.resolvedSemanticProfile
        let preferred = profile.preferredTimeWindows.filter { $0 != .anytime }
        let window = preferred.first ?? profile.preferredTimeWindows.first
        guard let window, window != .anytime, let hour = window.hours.filter({ $0 >= 5 }).sorted().first
                ?? window.hours.sorted().first else { return nil }
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: calendar.startOfDay(for: day))
    }

    public static func judge(_ input: Input) -> Verdict {
        let profile = input.task.resolvedSemanticProfile
        let calendar = input.calendar
        let start = input.proposedStart
        let duration = max(input.durationMinutes, TaskDurationPolicy.minimumMinutes)
        let window = TaskSemanticScheduler.currentTimeWindow(at: start, calendar: calendar)
        let inPreferred = isInPreferredWindow(profile, window: window)

        if profile.forbiddenTimeWindows.contains(window) {
            return .doesNotMakeSense("\(input.task.title) does not belong in the \(window.rawValue)")
        }

        if let box = TaskEphemeralityDefaults.boundingBox(for: input.task),
           !box.contains(start: start, calendar: calendar) {
            return .doesNotMakeSense("\(input.task.title) is outside its time fence")
        }

        if profile.schedulingConstraints.contains(.neverEveningDose),
           window == .evening || window == .night {
            return .doesNotMakeSense("This medication must not be taken in the evening")
        }

        if profile.schedulingConstraints.contains(.beforeBreakfast), window != .morning {
            return .doesNotMakeSense("This needs the morning, before breakfast")
        }

        if profile.schedulingConstraints.contains(.requiresStoreOpen),
           window == .night || (window == .evening && calendar.component(.hour, from: start) >= 20) {
            return .doesNotMakeSense("Stores are closed — this errand cannot sit this late")
        }

        if profile.schedulingConstraints.contains(.afterMealsForbidden),
           let mealEnd = recentMealEnd(before: start, input: input),
           start.timeIntervalSince(mealEnd) < 45 * 60 {
            return .doesNotMakeSense("Too soon after a meal — wait before physical activity")
        }

        if profile.semanticType == .medication, duration >= 30 {
            return .doesNotMakeSense("Medication does not need a long block")
        }

        let gap = freeMinutesAfter(
            start: start,
            occupied: input.occupied,
            taskID: input.task.id,
            dayEnd: resolvedDayEnd(input)
        )
        if profile.schedulingConstraints.contains(.requiresUninterruptedBlock),
           gap < min(duration, 45) {
            return .doesNotMakeSense("Needs a longer uninterrupted block than this gap")
        }

        if duration > gap + 5 {
            return .doesNotMakeSense("This \(duration)-minute block does not fit before the next commitment")
        }

        if !inPreferred {
            switch profile.flexibility {
            case .rigid, .low:
                return .doesNotMakeSense(
                    "\(input.task.title) belongs in the \(preferredLabel(profile)), not the \(window.rawValue)"
                )
            case .moderate:
                return .needsAI("Placement is off the usual window for a \(profile.semanticType.rawValue) task")
            case .high:
                break
            }
        }

        if window == .night, duration >= 45, profile.semanticType != .selfCare, profile.flexibility != .high {
            if profile.confidence < 0.7 || profile.semanticType == .generic {
                return .needsAI("A long night block needs a second look")
            }
            if profile.cognitiveRequirement == .deepFocus {
                return .doesNotMakeSense("Deep focus does not belong late at night")
            }
        }

        if profile.semanticType == .generic, profile.confidence < 0.65, !isOrdinaryDaytime(window) {
            return .needsAI("Not sure what this task is — need a meaning check before locking an unusual clock")
        }

        return .makesSense
    }

    /// Allocator search: only lock a slot the semantic layer is confident about.
    public static func isSearchableSlot(_ verdict: Verdict) -> Bool {
        if case .makesSense = verdict { return true }
        return false
    }

    private static func isInPreferredWindow(_ profile: TaskSemanticProfile, window: TimeWindowPreference) -> Bool {
        profile.preferredTimeWindows.contains(window)
            || profile.preferredTimeWindows.contains(.anytime)
            || profile.preferredTimeWindows.isEmpty
    }

    private static func isOrdinaryDaytime(_ window: TimeWindowPreference) -> Bool {
        window == .morning || window == .midday || window == .afternoon || window == .evening
    }

    private static func preferredLabel(_ profile: TaskSemanticProfile) -> String {
        let names = profile.preferredTimeWindows.filter { $0 != .anytime }.map(\.rawValue)
        if names.isEmpty { return "its usual window" }
        return names.joined(separator: " or ")
    }

    private static func resolvedDayEnd(_ input: Input) -> Date {
        if let dayEnd = input.dayEnd { return dayEnd }
        let day = input.calendar.startOfDay(for: input.proposedStart)
        return input.calendar.date(bySettingHour: 22, minute: 0, second: 0, of: day)
            ?? input.proposedStart.addingTimeInterval(8 * 3600)
    }

    private static func freeMinutesAfter(
        start: Date,
        occupied: [TaskScheduleInterval],
        taskID: String,
        dayEnd: Date
    ) -> Int {
        let next = occupied
            .filter { $0.taskID != taskID && $0.start > start }
            .map(\.start)
            .min()
        let fence = [next, dayEnd].compactMap { $0 }.min() ?? start.addingTimeInterval(8 * 3600)
        return max(0, Int(fence.timeIntervalSince(start) / 60))
    }

    private static func recentMealEnd(before start: Date, input: Input) -> Date? {
        let meals = input.neighborTasks.filter {
            $0.id != input.task.id && $0.resolvedSemanticProfile.subtype == "meal"
        }
        let ends = TaskScheduleInterval.intervals(from: meals, on: start, calendar: input.calendar)
            .filter { $0.end <= start }
            .map(\.end)
        return ends.max()
    }

    /// Night wraps midnight; keep the same-day cluster so bounds stay a single range.
    private static func workHours(from hours: Set<Int>) -> PlanningSchedulePolicy.WorkHours? {
        guard !hours.isEmpty else { return nil }
        let daytime = hours.filter { $0 >= 5 }
        let cluster = daytime.isEmpty ? hours : daytime
        guard let minHour = cluster.min(), let maxHour = cluster.max() else { return nil }
        return PlanningSchedulePolicy.WorkHours(
            startHour: minHour,
            startMinute: 0,
            endHour: min(23, maxHour),
            endMinute: 59
        )
    }
}
