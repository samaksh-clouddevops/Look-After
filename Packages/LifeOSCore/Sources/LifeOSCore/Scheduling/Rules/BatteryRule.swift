import Foundation

/// Shortens default Flow duration when battery is critically low.
public struct BatteryRule: FlowSchedulingRuleProtocol {
    public let lowBatteryThreshold: Float
    public let lowPowerCapMinutes: Int

    public let identifier = "BatteryRule"

    public init(lowBatteryThreshold: Float = 0.20, lowPowerCapMinutes: Int = 15) {
        self.lowBatteryThreshold = lowBatteryThreshold
        self.lowPowerCapMinutes = lowPowerCapMinutes
    }

    public func apply(to state: inout MutableSchedulingState, context: FlowSchedulingContext) {
        let battery = context.environment.batteryLevel
        let lowPower = context.environment.isLowPowerMode
        guard battery < lowBatteryThreshold || lowPower else { return }

        let cap = lowPower ? min(lowPowerCapMinutes, 10) : lowPowerCapMinutes
        state.maxDurationCap = min(state.maxDurationCap ?? cap, cap)

        if lowPower {
            state.reasoningLines.append("Low Power Mode — session shortened.")
        } else {
            state.reasoningLines.append("Battery below 20% — session shortened.")
        }
        state.appliedRuleIDs.append(identifier)
    }
}
