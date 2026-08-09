import Foundation
import LookAfterCore

/// WeatherKit-free stub (BUG-022 / R-024).
/// Always returns the configured condition — **must not** be weighted heavily by the brain.
/// Replace with a WeatherKit adapter in the app layer when enabled; keep `isAvailable == false`
/// until real signals are wired so capacity/scheduling treat weather as unknown.
public struct StubWeatherEnvironmentSignalProvider: WeatherEnvironmentSignalProviderProtocol {

    public var condition: WeatherCondition
    /// False by default so consumers know this is not a real weather feed.
    public var isAvailable: Bool
    public var shouldFail: Bool

    public init(
        condition: WeatherCondition = .unknown,
        isAvailable: Bool = false,
        shouldFail: Bool = false
    ) {
        self.condition = condition
        self.isAvailable = isAvailable
        self.shouldFail = shouldFail
    }

    public func currentSignals(at date: Date) async -> WeatherEnvironmentSignals {
        if shouldFail {
            return .unavailable
        }
        return WeatherEnvironmentSignals(condition: condition, isAvailable: isAvailable)
    }
}
