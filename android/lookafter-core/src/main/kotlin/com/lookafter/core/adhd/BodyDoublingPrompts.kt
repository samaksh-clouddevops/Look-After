package com.lookafter.core.adhd

/**
 * Calm body-doubling lines shown during focus (iOS body-double parity, text-only).
 * Pure / deterministic — no RNG so UI and tests stay stable for a given second offset.
 */
object BodyDoublingPrompts {

    private val standard = listOf(
        "I'm here with you. One breath, then the next small step.",
        "Stay with the block. Silence is productive.",
        "Eyes on the work. We can reassess when the timer ends.",
        "You don't need to finish everything — just this window.",
        "If friction appears, shrink the task. Keep moving.",
        "Shoulders down. Soft jaw. Continue.",
        "This is protected time. Interruptions can wait.",
        "Name the next microscopic action out loud, then do it.",
    )

    private val emergency = listOf(
        "Emergency mode: only this block matters for 10 minutes.",
        "Hard gate. Alarms only. Ride the clock.",
        "Tiny step. Then another. No narrative required.",
        "You are safe to ignore the rest of the board.",
        "When the timer ends, we renegotiate. Not before.",
        "Breathe once. Start the smallest doable slice.",
    )

    fun lineFor(
        elapsedActiveSeconds: Long,
        emergencyMode: Boolean = false,
    ): String {
        val pool = if (emergencyMode) emergency else standard
        // Rotate roughly every 45s of active work.
        val idx = ((elapsedActiveSeconds / 45).toInt() % pool.size).coerceAtLeast(0)
        return pool[idx]
    }

    fun poolSize(emergencyMode: Boolean = false): Int =
        if (emergencyMode) emergency.size else standard.size
}
