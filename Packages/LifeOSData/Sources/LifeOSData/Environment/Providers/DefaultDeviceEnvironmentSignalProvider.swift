import Foundation
import LifeOSCore

/// Reads device state via `ProcessInfo` and injectable overrides (no UIKit required in LifeOSCore).
public struct DefaultDeviceEnvironmentSignalProvider: DeviceEnvironmentSignalProviderProtocol {

    public var batteryLevelOverride: Float?
    public var isLowPowerModeOverride: Bool?
    public var reduceMotionOverride: Bool?
    public var focusModeEnabledOverride: Bool?
    public var shouldFail: Bool

    public init(
        batteryLevelOverride: Float? = nil,
        isLowPowerModeOverride: Bool? = nil,
        reduceMotionOverride: Bool? = nil,
        focusModeEnabledOverride: Bool? = nil,
        shouldFail: Bool = false
    ) {
        self.batteryLevelOverride = batteryLevelOverride
        self.isLowPowerModeOverride = isLowPowerModeOverride
        self.reduceMotionOverride = reduceMotionOverride
        self.focusModeEnabledOverride = focusModeEnabledOverride
        self.shouldFail = shouldFail
    }

    public func currentSignals() async -> DeviceEnvironmentSignals {
        if shouldFail {
            return .unavailable
        }

        return DeviceEnvironmentSignals(
            focusModeEnabled: focusModeEnabledOverride ?? false,
            batteryLevel: batteryLevelOverride ?? 1.0,
            isLowPowerMode: isLowPowerModeOverride ?? ProcessInfo.processInfo.isLowPowerModeEnabled,
            reduceMotionEnabled: reduceMotionOverride ?? false,
            isAvailable: true
        )
    }
}
