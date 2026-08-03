import XCTest
@testable import LifeOSData
import LifeOSCore

// MARK: - Mock Providers

private struct MockTimeProvider: TimeEnvironmentSignalProviderProtocol {
    var signals: TimeEnvironmentSignals
    var shouldFail: Bool = false

    func currentSignals(at date: Date, calendar: Calendar) async -> TimeEnvironmentSignals {
        shouldFail ? TimeEnvironmentSignals(isAvailable: false) : signals
    }
}

private struct MockHealthProvider: HealthEnvironmentSignalProviderProtocol {
    var signals: HealthEnvironmentSignals
    var shouldFail: Bool = false

    func currentSignals(
        cognitiveSnapshot: CognitiveSnapshot,
        healthSummary: HealthSummary?
    ) async -> HealthEnvironmentSignals {
        if shouldFail { return .unavailable }
        return signals
    }
}

private struct MockCalendarProvider: CalendarEnvironmentSignalProviderProtocol {
    var signals: CalendarEnvironmentSignals

    func currentSignals(at date: Date) async -> CalendarEnvironmentSignals {
        signals
    }
}

private struct MockDeviceProvider: DeviceEnvironmentSignalProviderProtocol {
    var signals: DeviceEnvironmentSignals
    var shouldFail: Bool = false

    func currentSignals() async -> DeviceEnvironmentSignals {
        shouldFail ? .unavailable : signals
    }
}

private struct MockWeatherProvider: WeatherEnvironmentSignalProviderProtocol {
    var signals: WeatherEnvironmentSignals
    var shouldFail: Bool = false

    func currentSignals(at date: Date) async -> WeatherEnvironmentSignals {
        shouldFail ? .unavailable : signals
    }
}

// MARK: - Tests

final class EnvironmentContextProviderTests: XCTestCase {

    private var calendar: Calendar!
    private var morningDate: Date!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 31
        components.hour = 8
        components.minute = 42
        morningDate = calendar.date(from: components)!
    }

    private func makeProvider(
        time: TimeEnvironmentSignals? = nil,
        health: HealthEnvironmentSignals? = nil,
        calendarSignals: CalendarEnvironmentSignals? = nil,
        device: DeviceEnvironmentSignals? = nil,
        weather: WeatherEnvironmentSignals? = nil,
        timeFails: Bool = false,
        healthFails: Bool = false,
        deviceFails: Bool = false,
        weatherFails: Bool = false
    ) -> EnvironmentContextProvider {
        EnvironmentContextProvider(
            timeProvider: MockTimeProvider(
                signals: time ?? TimeEnvironmentSignals(timeOfDay: .morning, isWeekend: false, isAvailable: true),
                shouldFail: timeFails
            ),
            healthProvider: MockHealthProvider(
                signals: health ?? HealthEnvironmentSignals(energyScore: 0.72, hrvDelta: 0.1, sleepQuality: .good, isAvailable: true),
                shouldFail: healthFails
            ),
            calendarProvider: MockCalendarProvider(
                signals: calendarSignals ?? CalendarEnvironmentSignals(freeBlockMinutes: 120, isAvailable: true)
            ),
            deviceProvider: MockDeviceProvider(
                signals: device ?? DeviceEnvironmentSignals(isAvailable: true),
                shouldFail: deviceFails
            ),
            weatherProvider: MockWeatherProvider(
                signals: weather ?? WeatherEnvironmentSignals(condition: .clear, isAvailable: true),
                shouldFail: weatherFails
            ),
            calendar: calendar
        )
    }

    private func snapshot(energy: Double = 0.72) -> CognitiveSnapshot {
        CognitiveSnapshot(energyScore: energy)
    }

    private func healthSummary(hrv: Double = 55, sleepHours: Double = 7.5) -> HealthSummary {
        var h = HealthSummary()
        h.hrvAverage = hrv
        h.totalSleepMinutes = sleepHours * 60
        h.sleepQualityScore = 0.75
        return h
    }

    // MARK: - Full Permissions

    func testFullPermissionsFusesAllSignals() async {
        let nextEvent = CalendarEventReference(
            id: "e1",
            title: "Team Sync",
            startDate: morningDate.addingTimeInterval(2700),
            endDate: morningDate.addingTimeInterval(5400),
            minutesUntilStart: 45
        )
        let provider = makeProvider(
            calendarSignals: CalendarEnvironmentSignals(
                nextEvent: nextEvent,
                freeBlockMinutes: 180,
                isAvailable: true
            ),
            device: DeviceEnvironmentSignals(
                batteryLevel: 0.85,
                isLowPowerMode: false,
                reduceMotionEnabled: false,
                isAvailable: true
            ),
            weather: WeatherEnvironmentSignals(condition: .rain, isAvailable: true)
        )

        let result = await provider.currentContext(
            cognitiveSnapshot: snapshot(),
            healthSummary: healthSummary(),
            at: morningDate
        )

        XCTAssertTrue(result.availability.health)
        XCTAssertTrue(result.availability.calendar)
        XCTAssertTrue(result.availability.weather)
        XCTAssertTrue(result.availability.device)
        XCTAssertTrue(result.availability.time)
        XCTAssertEqual(result.context.nextEvent?.title, "Team Sync")
        XCTAssertEqual(result.context.weather, .rain)
        XCTAssertEqual(result.context.energyScore, 0.72, accuracy: 0.001)
    }

    // MARK: - No Permissions

    func testNoCalendarPermissionReturnsPartialContext() async {
        let provider = makeProvider(
            calendarSignals: CalendarEnvironmentSignals(
                freeBlockMinutes: 0,
                isAvailable: false,
                permissionDenied: true
            )
        )

        let result = await provider.currentContext(
            cognitiveSnapshot: snapshot(),
            healthSummary: healthSummary(),
            at: morningDate
        )

        XCTAssertFalse(result.availability.calendar)
        XCTAssertNil(result.context.nextEvent)
        XCTAssertEqual(result.context.timeOfDay, .morning)
    }

    // MARK: - Missing Health

    func testMissingHealthDataDegradesGracefully() async {
        let healthProvider = DefaultHealthEnvironmentSignalProvider()
        let envProvider = EnvironmentContextProvider(
            healthProvider: healthProvider,
            calendar: calendar
        )

        let result = await envProvider.currentContext(
            cognitiveSnapshot: snapshot(energy: 0.55),
            healthSummary: nil,
            at: morningDate
        )

        XCTAssertFalse(result.availability.health)
        XCTAssertEqual(result.context.energyScore, 0.55, accuracy: 0.001)
        XCTAssertEqual(result.context.sleepQuality, .unknown)
    }

    // MARK: - Missing Calendar

    func testMissingCalendarDataUsesBaselineFreeBlock() async {
        let provider = makeProvider(
            calendarSignals: CalendarEnvironmentSignals.unavailable
        )

        let result = await provider.currentContext(
            cognitiveSnapshot: snapshot(),
            healthSummary: healthSummary(),
            at: morningDate
        )

        XCTAssertFalse(result.availability.calendar)
        XCTAssertEqual(result.context.freeBlockMinutes, EnvironmentContext.baseline.freeBlockMinutes)
    }

    // MARK: - Low Power Mode

    func testLowPowerModeReflectedInContext() async {
        let provider = makeProvider(
            device: DeviceEnvironmentSignals(
                batteryLevel: 0.15,
                isLowPowerMode: true,
                isAvailable: true
            )
        )

        let result = await provider.currentContext(
            cognitiveSnapshot: snapshot(),
            healthSummary: healthSummary(),
            at: morningDate
        )

        XCTAssertTrue(result.context.isLowPowerMode)
        XCTAssertEqual(result.context.batteryLevel, 0.15, accuracy: 0.01)
    }

    // MARK: - Reduce Motion

    func testReduceMotionReflectedInContext() async {
        let provider = makeProvider(
            device: DeviceEnvironmentSignals(
                reduceMotionEnabled: true,
                isAvailable: true
            )
        )

        let result = await provider.currentContext(
            cognitiveSnapshot: snapshot(),
            healthSummary: healthSummary(),
            at: morningDate
        )

        XCTAssertTrue(result.context.reduceMotionEnabled)
    }

    // MARK: - Time-of-Day Transitions

    func testTimeOfDayTransitionAfternoon() async {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 31
        components.hour = 14
        let afternoon = calendar.date(from: components)!

        let provider = makeProvider(
            time: TimeEnvironmentSignals(timeOfDay: .afternoon, isWeekend: false, isAvailable: true)
        )

        let result = await provider.currentContext(
            cognitiveSnapshot: snapshot(),
            healthSummary: healthSummary(),
            at: afternoon
        )

        XCTAssertEqual(result.context.timeOfDay, .afternoon)
        XCTAssertTrue(result.availability.time)
    }

    func testDefaultTimeProviderMorningAndNight() async {
        let timeProvider = DefaultTimeEnvironmentSignalProvider()
        var morningComponents = DateComponents()
        morningComponents.year = 2026
        morningComponents.month = 7
        morningComponents.day = 31
        morningComponents.hour = 8
        let morning = calendar.date(from: morningComponents)!

        var nightComponents = morningComponents
        nightComponents.hour = 22
        let night = calendar.date(from: nightComponents)!

        let morningSignals = await timeProvider.currentSignals(at: morning, calendar: calendar)
        let nightSignals = await timeProvider.currentSignals(at: night, calendar: calendar)

        XCTAssertEqual(morningSignals.timeOfDay, .morning)
        XCTAssertEqual(nightSignals.timeOfDay, .night)
    }

    // MARK: - Provider Failures

    func testProviderFailuresReturnPartialContext() async {
        let provider = makeProvider(
            weather: WeatherEnvironmentSignals.unavailable,
            timeFails: false,
            healthFails: true,
            deviceFails: true,
            weatherFails: true
        )

        let result = await provider.currentContext(
            cognitiveSnapshot: snapshot(energy: 0.6),
            healthSummary: healthSummary(),
            at: morningDate
        )

        XCTAssertFalse(result.availability.health)
        XCTAssertFalse(result.availability.device)
        XCTAssertFalse(result.availability.weather)
        XCTAssertTrue(result.availability.time)
        XCTAssertEqual(result.context.weather, WeatherCondition.unknown)
    }

    // MARK: - Concurrent Reads

    func testConcurrentReads() async {
        let provider = makeProvider()

        await withTaskGroup(of: EnvironmentContextResult.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    await provider.currentContext(
                        cognitiveSnapshot: self.snapshot(),
                        healthSummary: self.healthSummary(),
                        at: self.morningDate
                    )
                }
            }
            var count = 0
            for await result in group {
                XCTAssertEqual(result.context.timeOfDay, .morning)
                count += 1
            }
            XCTAssertEqual(count, 50)
        }
    }

    // MARK: - Legacy Protocol

    func testEnvironmentContextProviderProtocolReturnsContextOnly() async {
        let provider = makeProvider()
        let context = await provider.currentContext(
            cognitiveSnapshot: snapshot(),
            healthSummary: healthSummary()
        )
        XCTAssertEqual(context.timeOfDay, .morning)
    }

    // MARK: - Health HRV Delta

    func testHealthProviderComputesHRVDelta() async {
        let healthProvider = DefaultHealthEnvironmentSignalProvider(hrvBaselineMs: 50)
        let signals = await healthProvider.currentSignals(
            cognitiveSnapshot: snapshot(),
            healthSummary: healthSummary(hrv: 60)
        )
        XCTAssertTrue(signals.isAvailable)
        XCTAssertEqual(signals.hrvDelta, 0.2, accuracy: 0.01)
    }

    // MARK: - Weather Stub

    func testWeatherStubDisabledByDefault() async {
        let stub = StubWeatherEnvironmentSignalProvider()
        let signals = await stub.currentSignals(at: morningDate)
        XCTAssertFalse(signals.isAvailable)
        XCTAssertEqual(signals.condition, .unknown)
    }
}
