import Foundation
import LookAfterCore

/// Lightweight remaining-flex estimate for Capture capacity gating.
enum CaptureCapacityContext {
    static func remainingFlexMinutes(
        energyPercent: Int = 55,
        bookedFlexMinutes: Int? = nil
    ) -> Int {
        let budget: Int
        switch energyPercent {
        case ..<35: budget = 90
        case ..<60: budget = 180
        default: budget = 270
        }
        let booked = bookedFlexMinutes ?? 0
        return max(0, budget - booked)
    }
}
