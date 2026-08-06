import Foundation

/// Computes when the actionable day ends — sleep / wind-down marks the timeline fence.
public enum DayBoundaryPlanner {

    public struct Context: Sendable {
        public var profile: UserLifeProfile
        public var targetSleepHours: Double
        public var tasks: [LifeTask]
        public var timelineEvents: [LifeTimelineEvent]
        public var lifeModel: LifeModel?

        public init(
            profile: UserLifeProfile = UserLifeProfileStore.load(),
            targetSleepHours: Double = IdealSleepPlanner.defaultTargetSleepHours(),
            tasks: [LifeTask] = [],
            timelineEvents: [LifeTimelineEvent] = [],
            lifeModel: LifeModel? = LifeModelStore.load()
        ) {
            self.profile = profile
            self.targetSleepHours = targetSleepHours
            self.tasks = tasks
            self.timelineEvents = timelineEvents
            self.lifeModel = lifeModel
        }
    }

    /// Last moment flexible / unscheduled work should occupy on a calendar day.
    public static func actionableDayEnd(
        on day: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        context: Context = Context()
    ) -> Date {
        if let bedtime = recommendedBedtime(on: day, now: now, calendar: calendar, context: context) {
            return bedtime
        }
        return fallbackWindDown(on: day, profile: context.profile, calendar: calendar)
    }

    /// Ideal sleep start for timeline display and AI scheduling fences.
    public static func recommendedBedtime(
        on day: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        context: Context = Context()
    ) -> Date? {
        let dayStart = calendar.startOfDay(for: day)
        let input = IdealSleepPlanner.Input(
            now: max(now, dayStart),
            targetSleepHours: context.targetSleepHours,
            todayTimelineEvents: context.timelineEvents.filter {
                calendar.isDate($0.date, inSameDayAs: day)
            },
            tomorrowTimelineEvents: [],
            tasks: context.tasks,
            profile: context.profile,
            lifeModel: context.lifeModel,
            calendar: calendar,
            showFromHour: 0
        )
        if let recommendation = IdealSleepPlanner.recommend(input),
           calendar.isDate(recommendation.bedtime, inSameDayAs: day) {
            return recommendation.bedtime
        }
        return nil
    }

    private static let sleepTimelineShowFromHour = 17

    /// Sleep / wind-down row for the life timeline — fixed anchor at end of day.
    public static func sleepTimelineEvent(
        on day: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        context: Context = Context()
    ) -> LifeTimelineEvent? {
        let hour = calendar.component(.hour, from: now)
        guard hour >= sleepTimelineShowFromHour else { return nil }

        let bedtime = actionableDayEnd(on: day, now: now, calendar: calendar, context: context)
        guard calendar.isDate(bedtime, inSameDayAs: day) else { return nil }

        let label = ScheduleTimeFormatting.timeLabel(bedtime, calendar: calendar)
        return LifeTimelineEvent(
            id: "sleep-boundary-\(Int(day.timeIntervalSince1970))",
            kind: .recovery,
            title: "Wind down · Sleep",
            subtitle: "Ideal by \(label)",
            date: bedtime,
            estimatedMinutes: 30,
            isFixed: true
        )
    }

    private static func fallbackWindDown(
        on day: Date,
        profile: UserLifeProfile,
        calendar: Calendar
    ) -> Date {
        let dayStart = calendar.startOfDay(for: day)
        if let defaultBedtime = calendar.date(bySettingHour: 22, minute: 30, second: 0, of: dayStart) {
            return defaultBedtime
        }
        let hour = profile.workEndHour > 0 ? min(max(profile.workEndHour + 3, 21), 23) : 22
        let minute = profile.workEndHour > 0 ? profile.workEndMinute : 30
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart)
            ?? dayStart.addingTimeInterval(22.5 * 3600)
    }
}
