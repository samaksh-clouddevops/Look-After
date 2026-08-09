import Foundation

/// Maps briefing health snapshot fields to You-tab Life State progress bars.
/// Keeps Energy / Focus / Wellbeing aligned with Briefing → "How you're doing".
public enum LifeStateProgressResolver {

    public struct Progress: Sendable, Equatable {
        public var energy: Double
        public var focus: Double
        public var wellbeing: Double

        public init(energy: Double, focus: Double, wellbeing: Double) {
            self.energy = energy
            self.focus = focus
            self.wellbeing = wellbeing
        }
    }

    /// - Energy: `BriefingHealthSnapshot.energyPercent` (same tile as Briefing strip).
    /// - Focus: `readinessScore` — executive-function readiness shown in briefing chapter copy.
    /// - Wellbeing: `recoveryPercent` — same signal as Briefing Recovery tile.
    public static func resolve(
        healthSnapshot: BriefingHealthSnapshot,
        sleep: BriefingSleepData = BriefingSleepData(isAvailable: false)
    ) -> Progress {
        let energy = Double(healthSnapshot.energyPercent) / 100.0
        let focus = Double(healthSnapshot.readinessScore) / 100.0

        let wellbeing: Double
        if healthSnapshot.hasOvernightHealthSignal || healthSnapshot.recoveryPercent > 0 {
            wellbeing = Double(healthSnapshot.recoveryPercent) / 100.0
        } else if sleep.isAvailable, let hours = sleep.totalHours {
            // When recovery isn't available yet, mirror the Sleep tile until overnight metrics land.
            wellbeing = min(max(hours / 8.0, 0), 1)
        } else {
            wellbeing = 0
        }

        return Progress(
            energy: clamp(energy),
            focus: clamp(focus),
            wellbeing: clamp(wellbeing)
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
