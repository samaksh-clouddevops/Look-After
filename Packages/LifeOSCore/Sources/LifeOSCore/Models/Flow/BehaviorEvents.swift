import Foundation

// MARK: - Event Kind

/// Discriminator for append-only behavioral events collected by Behavior Memory.
/// Raw events are persisted in D2.2; inference derives `BehaviorPattern` values in a later milestone.
public enum BehaviorEventKind: String, Codable, Sendable, CaseIterable {
    /// User completed a task.
    case taskCompletion
    /// User deferred a task ("not now").
    case taskDeferral
    /// User ended a Flow session (focus timer).
    case flowSessionEnded
}

// MARK: - Context Metadata

/// Lightweight environmental snapshot captured at the moment a behavior event occurs.
/// Stored alongside each event so future inference can correlate energy, time, and context
/// without re-querying HealthKit or WeatherKit retroactively.
public struct BehaviorContextMetadata: Codable, Sendable, Equatable {
    public var energyScore: Double
    public var flowPersonality: FlowPersonality
    public var timeOfDay: TimeOfDay
    /// Hour of day in local calendar (0–23).
    public var hourOfDay: Int
    /// Weekday in local calendar (1 = Sunday … 7 = Saturday).
    public var dayOfWeek: Int
    public var weather: WeatherCondition
    public var sleepQuality: SleepQuality
    public var focusModeEnabled: Bool
    public var isWeekend: Bool
    public var locationContext: LocationContext?

    public init(
        energyScore: Double,
        flowPersonality: FlowPersonality,
        timeOfDay: TimeOfDay,
        hourOfDay: Int,
        dayOfWeek: Int,
        weather: WeatherCondition,
        sleepQuality: SleepQuality,
        focusModeEnabled: Bool,
        isWeekend: Bool,
        locationContext: LocationContext? = nil
    ) {
        self.energyScore = min(max(energyScore, 0), 1)
        self.flowPersonality = flowPersonality
        self.timeOfDay = timeOfDay
        self.hourOfDay = hourOfDay
        self.dayOfWeek = dayOfWeek
        self.weather = weather
        self.sleepQuality = sleepQuality
        self.focusModeEnabled = focusModeEnabled
        self.isWeekend = isWeekend
        self.locationContext = locationContext
    }

    /// Builds metadata from a fused `EnvironmentContext` at a specific instant.
    public static func from(
        context: EnvironmentContext,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> BehaviorContextMetadata {
        BehaviorContextMetadata(
            energyScore: context.energyScore,
            flowPersonality: FlowPersonality.from(energyScore: context.energyScore),
            timeOfDay: context.timeOfDay,
            hourOfDay: calendar.component(.hour, from: date),
            dayOfWeek: calendar.component(.weekday, from: date),
            weather: context.weather,
            sleepQuality: context.sleepQuality,
            focusModeEnabled: context.focusModeEnabled,
            isWeekend: context.isWeekend,
            locationContext: context.locationContext
        )
    }
}

// MARK: - Behavior Event

/// Append-only behavioral event log entry.
/// Behavior Memory collects these in D2.2; Flow Director consumes aggregated snapshots until inference ships.
public struct BehaviorEvent: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: BehaviorEventKind
    public var taskID: String?
    public var taskTitle: String?
    /// `LifeArea.rawValue` at event time for life-area correlation (future inference).
    public var lifeAreaRawValue: String?
    public var recordedAt: Date
    /// Actual or estimated duration in minutes (completions and Flow sessions).
    public var durationMinutes: Int?
    public var context: BehaviorContextMetadata

    public init(
        id: String = UUID().uuidString,
        kind: BehaviorEventKind,
        taskID: String? = nil,
        taskTitle: String? = nil,
        lifeAreaRawValue: String? = nil,
        recordedAt: Date = Date(),
        durationMinutes: Int? = nil,
        context: BehaviorContextMetadata
    ) {
        self.id = id
        self.kind = kind
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.lifeAreaRawValue = lifeAreaRawValue
        self.recordedAt = recordedAt
        self.durationMinutes = durationMinutes
        self.context = context
    }
}

/// Factory helpers for common event types.
public enum BehaviorEventFactory {
    public static func completion(
        task: LifeTask,
        durationMinutes: Int,
        context: EnvironmentContext,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> BehaviorEvent {
        BehaviorEvent(
            kind: .taskCompletion,
            taskID: task.id,
            taskTitle: task.title,
            lifeAreaRawValue: task.lifeArea.rawValue,
            recordedAt: date,
            durationMinutes: max(durationMinutes, 0),
            context: .from(context: context, at: date, calendar: calendar)
        )
    }

    public static func deferral(
        task: LifeTask,
        context: EnvironmentContext?,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> BehaviorEvent {
        BehaviorEvent(
            kind: .taskDeferral,
            taskID: task.id,
            taskTitle: task.title,
            lifeAreaRawValue: task.lifeArea.rawValue,
            recordedAt: date,
            context: .from(context: context ?? .baseline, at: date, calendar: calendar)
        )
    }

    public static func flowSessionEnded(
        task: LifeTask?,
        durationMinutes: Int,
        context: EnvironmentContext,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> BehaviorEvent {
        BehaviorEvent(
            kind: .flowSessionEnded,
            taskID: task?.id,
            taskTitle: task?.title,
            lifeAreaRawValue: task?.lifeArea.rawValue,
            recordedAt: date,
            durationMinutes: max(durationMinutes, 0),
            context: .from(context: context, at: date, calendar: calendar)
        )
    }
}
