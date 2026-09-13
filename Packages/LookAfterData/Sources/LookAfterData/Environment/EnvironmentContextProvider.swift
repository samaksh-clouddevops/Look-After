import Foundation
import LookAfterCore

/// Read-only fusion of injected environment signal providers (D2.3).
///
/// Never imports platform frameworks. Never throws — returns partial `EnvironmentContext`
/// when individual providers are unavailable or denied.
public struct EnvironmentContextProvider: EnvironmentContextProviding, EnvironmentContextProviderProtocol {

    public let timeProvider: TimeEnvironmentSignalProviderProtocol
    public let healthProvider: HealthEnvironmentSignalProviderProtocol
    public let calendarProvider: CalendarEnvironmentSignalProviderProtocol
    public let deviceProvider: DeviceEnvironmentSignalProviderProtocol
    public let weatherProvider: WeatherEnvironmentSignalProviderProtocol
    public let locationProvider: LocationEnvironmentSignalProviderProtocol
    public let calendar: Calendar

    public init(
        timeProvider: TimeEnvironmentSignalProviderProtocol = DefaultTimeEnvironmentSignalProvider(),
        healthProvider: HealthEnvironmentSignalProviderProtocol = DefaultHealthEnvironmentSignalProvider(),
        calendarProvider: CalendarEnvironmentSignalProviderProtocol = UnavailableCalendarEnvironmentSignalProvider(permissionDenied: false),
        deviceProvider: DeviceEnvironmentSignalProviderProtocol = DefaultDeviceEnvironmentSignalProvider(),
        weatherProvider: WeatherEnvironmentSignalProviderProtocol = StubWeatherEnvironmentSignalProvider(),
        locationProvider: LocationEnvironmentSignalProviderProtocol = UnavailableLocationEnvironmentSignalProvider(),
        calendar: Calendar = .current
    ) {
        self.timeProvider = timeProvider
        self.healthProvider = healthProvider
        self.calendarProvider = calendarProvider
        self.deviceProvider = deviceProvider
        self.weatherProvider = weatherProvider
        self.locationProvider = locationProvider
        self.calendar = calendar
    }

    // MARK: - EnvironmentContextProviding

    public func currentContext(
        cognitiveSnapshot: CognitiveSnapshot,
        healthSummary: HealthSummary?,
        at date: Date = Date()
    ) async -> EnvironmentContextResult {
        async let timeSignals = timeProvider.currentSignals(at: date, calendar: calendar)
        async let healthSignals = healthProvider.currentSignals(
            cognitiveSnapshot: cognitiveSnapshot,
            healthSummary: healthSummary
        )
        async let calendarSignals = calendarProvider.currentSignals(at: date)
        async let deviceSignals = deviceProvider.currentSignals()
        async let weatherSignals = weatherProvider.currentSignals(at: date)
        async let locationSignals = locationProvider.currentSignals()

        let (time, health, cal, device, weather, location) = await (
            timeSignals, healthSignals, calendarSignals, deviceSignals, weatherSignals, locationSignals
        )

        let availability = EnvironmentSignalAvailability(
            health: health.isAvailable,
            calendar: cal.isAvailable,
            weather: weather.isAvailable,
            device: device.isAvailable,
            time: time.isAvailable,
            location: location.isAvailable
        )

        let context = EnvironmentContext(
            energyScore: health.isAvailable ? health.energyScore : cognitiveSnapshot.energyScore,
            hrvDelta: health.hrvDelta,
            sleepQuality: health.isAvailable ? health.sleepQuality : .unknown,
            nextEvent: cal.nextEvent,
            freeBlockMinutes: cal.isAvailable ? cal.freeBlockMinutes : EnvironmentContext.baseline.freeBlockMinutes,
            flowWindow: cal.flowWindow,
            weather: weather.isAvailable ? weather.condition : .unknown,
            timeOfDay: time.timeOfDay,
            isWeekend: time.isWeekend,
            focusModeEnabled: device.focusModeEnabled,
            batteryLevel: device.isAvailable ? device.batteryLevel : 1.0,
            isLowPowerMode: device.isLowPowerMode,
            reduceMotionEnabled: device.reduceMotionEnabled,
            ambientNoiseLevel: nil,
            locationContext: location.isAvailable ? location.locationContext : nil
        )

        return EnvironmentContextResult(context: context, availability: availability)
    }

    // MARK: - EnvironmentContextProviderProtocol

    public func currentContext(
        cognitiveSnapshot: CognitiveSnapshot,
        healthSummary: HealthSummary?
    ) async -> EnvironmentContext {
        await currentContext(
            cognitiveSnapshot: cognitiveSnapshot,
            healthSummary: healthSummary,
            at: Date()
        ).context
    }
}
