import Foundation

// MARK: - Signal Availability

/// Indicates which environment signal sources contributed to a fused `EnvironmentContext`.
public struct EnvironmentSignalAvailability: Codable, Sendable, Equatable {
    public var health: Bool
    public var calendar: Bool
    public var weather: Bool
    public var device: Bool
    public var time: Bool

    public init(
        health: Bool = false,
        calendar: Bool = false,
        weather: Bool = false,
        device: Bool = false,
        time: Bool = true
    ) {
        self.health = health
        self.calendar = calendar
        self.weather = weather
        self.device = device
        self.time = time
    }

    public static let none = EnvironmentSignalAvailability(time: false)
}

// MARK: - Health Signals

/// Health-derived slice of `EnvironmentContext` (no HealthKit imports in LifeOSCore).
public struct HealthEnvironmentSignals: Sendable, Equatable {
    public var energyScore: Double
    public var hrvDelta: Double
    public var sleepQuality: SleepQuality
    public var isAvailable: Bool

    public init(
        energyScore: Double = 0.5,
        hrvDelta: Double = 0,
        sleepQuality: SleepQuality = .unknown,
        isAvailable: Bool = false
    ) {
        self.energyScore = min(max(energyScore, 0), 1)
        self.hrvDelta = hrvDelta
        self.sleepQuality = sleepQuality
        self.isAvailable = isAvailable
    }

    public static let unavailable = HealthEnvironmentSignals()
}

/// Reads health context from already-fetched summaries (HealthKit stays in LifeOSHealth / app layer).
public protocol HealthEnvironmentSignalProviderProtocol: Sendable {
    func currentSignals(
        cognitiveSnapshot: CognitiveSnapshot,
        healthSummary: HealthSummary?
    ) async -> HealthEnvironmentSignals
}

// MARK: - Calendar Signals

/// Calendar-derived slice of `EnvironmentContext`.
public struct CalendarEnvironmentSignals: Sendable, Equatable {
    public var nextEvent: CalendarEventReference?
    public var freeBlockMinutes: Int
    public var flowWindow: DateInterval?
    public var isAvailable: Bool
    public var permissionDenied: Bool

    public init(
        nextEvent: CalendarEventReference? = nil,
        freeBlockMinutes: Int = 0,
        flowWindow: DateInterval? = nil,
        isAvailable: Bool = false,
        permissionDenied: Bool = false
    ) {
        self.nextEvent = nextEvent
        self.freeBlockMinutes = max(freeBlockMinutes, 0)
        self.flowWindow = flowWindow
        self.isAvailable = isAvailable
        self.permissionDenied = permissionDenied
    }

    public static let unavailable = CalendarEnvironmentSignals(permissionDenied: false)
}

public protocol CalendarEnvironmentSignalProviderProtocol: Sendable {
    func currentSignals(at date: Date) async -> CalendarEnvironmentSignals
}

// MARK: - Device Signals

/// Device state slice of `EnvironmentContext`.
public struct DeviceEnvironmentSignals: Sendable, Equatable {
    public var focusModeEnabled: Bool
    public var batteryLevel: Float
    public var isLowPowerMode: Bool
    public var reduceMotionEnabled: Bool
    public var isAvailable: Bool

    public init(
        focusModeEnabled: Bool = false,
        batteryLevel: Float = 1.0,
        isLowPowerMode: Bool = false,
        reduceMotionEnabled: Bool = false,
        isAvailable: Bool = false
    ) {
        self.focusModeEnabled = focusModeEnabled
        self.batteryLevel = min(max(batteryLevel, 0), 1)
        self.isLowPowerMode = isLowPowerMode
        self.reduceMotionEnabled = reduceMotionEnabled
        self.isAvailable = isAvailable
    }

    public static let unavailable = DeviceEnvironmentSignals()
}

public protocol DeviceEnvironmentSignalProviderProtocol: Sendable {
    func currentSignals() async -> DeviceEnvironmentSignals
}

// MARK: - Weather Signals

/// Weather slice of `EnvironmentContext`. WeatherKit implementations live outside LifeOSCore.
public struct WeatherEnvironmentSignals: Sendable, Equatable {
    public var condition: WeatherCondition
    public var isAvailable: Bool

    public init(condition: WeatherCondition = .unknown, isAvailable: Bool = false) {
        self.condition = condition
        self.isAvailable = isAvailable
    }

    public static let unavailable = WeatherEnvironmentSignals()
}

public protocol WeatherEnvironmentSignalProviderProtocol: Sendable {
    func currentSignals(at date: Date) async -> WeatherEnvironmentSignals
}

// MARK: - Time Signals

/// Time-of-day slice of `EnvironmentContext` (pure Foundation, always available).
public struct TimeEnvironmentSignals: Sendable, Equatable {
    public var timeOfDay: TimeOfDay
    public var isWeekend: Bool
    public var isAvailable: Bool

    public init(
        timeOfDay: TimeOfDay = .morning,
        isWeekend: Bool = false,
        isAvailable: Bool = true
    ) {
        self.timeOfDay = timeOfDay
        self.isWeekend = isWeekend
        self.isAvailable = isAvailable
    }
}

public protocol TimeEnvironmentSignalProviderProtocol: Sendable {
    func currentSignals(at date: Date, calendar: Calendar) async -> TimeEnvironmentSignals
}

// MARK: - Fused Result

/// Read-only output of `EnvironmentContextProvider` including partial availability metadata.
public struct EnvironmentContextResult: Sendable, Equatable {
    public var context: EnvironmentContext
    public var availability: EnvironmentSignalAvailability

    public init(context: EnvironmentContext, availability: EnvironmentSignalAvailability) {
        self.context = context
        self.availability = availability
    }
}

/// Extended provider protocol returning availability metadata (D2.3).
public protocol EnvironmentContextProviding: Sendable {
    func currentContext(
        cognitiveSnapshot: CognitiveSnapshot,
        healthSummary: HealthSummary?,
        at date: Date
    ) async -> EnvironmentContextResult
}
