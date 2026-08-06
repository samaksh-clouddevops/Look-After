package com.lookafter.core.planning

import com.lookafter.core.models.CascadeActionKind
import com.lookafter.core.models.CascadeActionLog
import kotlin.math.max
import kotlin.math.min

/**
 * Pure aggregator over [CascadeActionLog] entries for weekly review surfaces.
 *
 * Computes:
 * - total focus hours
 * - time reclaimed (from sabotage auctions / recovery enforcement)
 * - equilibrium score clamped to [[MIN_EQUILIBRIUM], [MAX_EQUILIBRIUM]]
 */
object WeeklyReviewAggregator {

    const val MIN_EQUILIBRIUM: Double = 0.2
    const val MAX_EQUILIBRIUM: Double = 1.0

    data class WeeklyReviewMetrics(
        /** Sum of focus minutes / 60. */
        val totalFocusHours: Double,
        /** Minutes reclaimed via sabotage auctions / recovery locks, as hours. */
        val timeReclaimedHours: Double,
        /**
         * Balance of sustained focus vs disruption pressure.
         * Clamped to [MIN_EQUILIBRIUM]..[MAX_EQUILIBRIUM].
         */
        val equilibriumScore: Double,
        val focusMinutes: Int,
        val reclaimedMinutes: Int,
        val sabotageAuctionCount: Int,
        val shiftLaterCount: Int,
        val supersededCount: Int,
        val expiredCount: Int,
        val parkedCount: Int,
    )

    fun aggregate(logs: List<CascadeActionLog>): WeeklyReviewMetrics {
        var focusMinutes = 0
        var reclaimedMinutes = 0
        var sabotage = 0
        var shifted = 0
        var superseded = 0
        var expired = 0
        var parked = 0

        for (log in logs) {
            focusMinutes += max(0, log.focusMinutes)
            reclaimedMinutes += max(0, log.reclaimedMinutes)

            when (log.action) {
                CascadeActionKind.SABOTAGE_AUCTION -> {
                    sabotage += 1
                    // Sabotage auctions always reclaim their declared recovery minutes.
                    if (log.reclaimedMinutes <= 0 && log.focusMinutes > 0) {
                        // defensive: treat focusMinutes as reclaimed when mis-tagged
                        reclaimedMinutes += log.focusMinutes
                    }
                }
                CascadeActionKind.SHIFTED_LATER -> shifted += 1
                CascadeActionKind.SUPERSEDED -> superseded += 1
                CascadeActionKind.EXPIRED -> expired += 1
                CascadeActionKind.PARKED -> parked += 1
                CascadeActionKind.COMPRESSED,
                CascadeActionKind.DEFERRED,
                CascadeActionKind.FOCUS_COMPLETED,
                CascadeActionKind.KEEP,
                -> Unit
            }
        }

        val focusHours = focusMinutes / 60.0
        val reclaimedHours = reclaimedMinutes / 60.0
        val equilibrium = equilibriumScore(
            focusMinutes = focusMinutes,
            reclaimedMinutes = reclaimedMinutes,
            disruptionCount = shifted + superseded + expired + parked,
            sabotageCount = sabotage,
        )

        return WeeklyReviewMetrics(
            totalFocusHours = focusHours,
            timeReclaimedHours = reclaimedHours,
            equilibriumScore = equilibrium,
            focusMinutes = focusMinutes,
            reclaimedMinutes = reclaimedMinutes,
            sabotageAuctionCount = sabotage,
            shiftLaterCount = shifted,
            supersededCount = superseded,
            expiredCount = expired,
            parkedCount = parked,
        )
    }

    /**
     * Equilibrium blends sustained focus with recovery reclaim and penalizes thrash.
     *
     * base = 0.55
     * + up to 0.30 from focus density (120 focus-min ≈ full focus bonus)
     * + up to 0.20 from reclaim density (60 reclaim-min ≈ full reclaim bonus)
     * − 0.05 per disruption event (shift / supersede / expire / park)
     * + 0.08 per sabotage auction (recovery protection is healthy)
     */
    fun equilibriumScore(
        focusMinutes: Int,
        reclaimedMinutes: Int,
        disruptionCount: Int,
        sabotageCount: Int,
    ): Double {
        val focusBonus = min(0.30, (max(0, focusMinutes) / 120.0) * 0.30)
        val reclaimBonus = min(0.20, (max(0, reclaimedMinutes) / 60.0) * 0.20)
        val disruptionPenalty = disruptionCount * 0.05
        val sabotageBonus = sabotageCount * 0.08
        val raw = 0.55 + focusBonus + reclaimBonus - disruptionPenalty + sabotageBonus
        return clamp(raw, MIN_EQUILIBRIUM, MAX_EQUILIBRIUM)
    }

    private fun clamp(value: Double, minValue: Double, maxValue: Double): Double =
        min(maxValue, max(minValue, value))
}
