package com.lookafter.core.planning

import com.lookafter.core.models.CascadeActionKind
import com.lookafter.core.models.CascadeActionLog
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class WeeklyReviewAggregatorTest {

    @Test
    fun `aggregates focus hours and reclaimed time`() {
        val logs = listOf(
            CascadeActionLog(
                action = CascadeActionKind.FOCUS_COMPLETED,
                focusMinutes = 90,
            ),
            CascadeActionLog(
                action = CascadeActionKind.FOCUS_COMPLETED,
                focusMinutes = 30,
            ),
            CascadeActionLog(
                action = CascadeActionKind.SABOTAGE_AUCTION,
                reclaimedMinutes = 45,
                reason = "recovery-block",
            ),
            CascadeActionLog(
                action = CascadeActionKind.SHIFTED_LATER,
                shiftMinutes = 40,
            ),
        )

        val metrics = WeeklyReviewAggregator.aggregate(logs)
        assertEquals(2.0, metrics.totalFocusHours, absoluteTolerance = 1e-9)
        assertEquals(0.75, metrics.timeReclaimedHours, absoluteTolerance = 1e-9)
        assertEquals(1, metrics.sabotageAuctionCount)
        assertEquals(1, metrics.shiftLaterCount)
        assertTrue(metrics.equilibriumScore in 0.2..1.0)
    }

    @Test
    fun `equilibrium score is clamped between 0_2 and 1_0`() {
        val empty = WeeklyReviewAggregator.equilibriumScore(
            focusMinutes = 0,
            reclaimedMinutes = 0,
            disruptionCount = 100,
            sabotageCount = 0,
        )
        assertEquals(0.2, empty, absoluteTolerance = 1e-9)

        val perfect = WeeklyReviewAggregator.equilibriumScore(
            focusMinutes = 10_000,
            reclaimedMinutes = 10_000,
            disruptionCount = 0,
            sabotageCount = 50,
        )
        assertEquals(1.0, perfect, absoluteTolerance = 1e-9)
    }

    @Test
    fun `empty log yields zero focus and baseline equilibrium`() {
        val metrics = WeeklyReviewAggregator.aggregate(emptyList())
        assertEquals(0.0, metrics.totalFocusHours)
        assertEquals(0.0, metrics.timeReclaimedHours)
        assertEquals(0.55, metrics.equilibriumScore, absoluteTolerance = 1e-9)
    }
}
