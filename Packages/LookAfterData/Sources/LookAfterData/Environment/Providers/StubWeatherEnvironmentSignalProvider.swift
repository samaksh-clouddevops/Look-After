import Foundation
import LookAfterCore

/// WeatherKit-free stub. Replace with a WeatherKit adapter in the app layer when enabled.
public struct StubWeatherEnvironmentSignalProvider: WeatherEnvironmentSignalProviderProtocol {

    public var condition: WeatherCondition
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
