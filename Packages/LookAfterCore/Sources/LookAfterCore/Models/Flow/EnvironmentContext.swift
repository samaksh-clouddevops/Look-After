import Foundation

/// Fused real-world signals used by Flow Director for orchestration and UI adaptation.
/// Built by `EnvironmentContextProvider` (LookAfterData / app layer) on each orchestration cycle.
public struct EnvironmentContext: Codable, Sendable, Equatable {
    // MARK: - Health

    public var energyScore: Double
    /// Delta vs 7-day HRV baseline (positive = above baseline).
    public var hrvDelta: Double
    public var sleepQuality: SleepQuality

    // MARK: - Calendar

    public var nextEvent: CalendarEventReference?
    public var freeBlockMinutes: Int
    public var flowWindow: DateInterval?

    // MARK: - World

    public var weather: WeatherCondition
    public var timeOfDay: TimeOfDay
    public var isWeekend: Bool

    // MARK: - Device

    public var focusModeEnabled: Bool
    public var batteryLevel: Float
    public var isLowPowerMode: Bool
    public var reduceMotionEnabled: Bool

    // MARK: - Optional (permission-gated)

    public var ambientNoiseLevel: NoiseLevel?
    public var locationContext: LocationContext?

    public init(
        energyScore: Double = 0.5,
        hrvDelta: Double = 0,
        sleepQuality: SleepQuality = .unknown,
        nextEvent: CalendarEventReference? = nil,
        freeBlockMinutes: Int = 480,
        flowWindow: DateInterval? = nil,
        weather: WeatherCondition = .unknown,
        timeOfDay: TimeOfDay = .morning,
        isWeekend: Bool = false,
        focusModeEnabled: Bool = false,
        batteryLevel: Float = 1.0,
        isLowPowerMode: Bool = false,
        reduceMotionEnabled: Bool = false,
        ambientNoiseLevel: NoiseLevel? = nil,
        locationContext: LocationContext? = nil
    ) {
        self.energyScore = min(max(energyScore, 0), 1)
        self.hrvDelta = hrvDelta
        self.sleepQuality = sleepQuality
        self.nextEvent = nextEvent
        self.freeBlockMinutes = max(freeBlockMinutes, 0)
        self.flowWindow = flowWindow
        self.weather = weather
        self.timeOfDay = timeOfDay
        self.isWeekend = isWeekend
        self.focusModeEnabled = focusModeEnabled
        self.batteryLevel = min(max(batteryLevel, 0), 1)
        self.isLowPowerMode = isLowPowerMode
        self.reduceMotionEnabled = reduceMotionEnabled
        self.ambientNoiseLevel = ambientNoiseLevel
        self.locationContext = locationContext
    }

    /// Neutral baseline when providers are unavailable.
    public static let baseline = EnvironmentContext(
        timeOfDay: TimeOfDay.from(date: Date())
    )
}
