package com.lookafter.core.models

import com.lookafter.core.serialization.InstantSerializer
import com.lookafter.core.serialization.LocalTimeSerializer
import java.time.Instant
import java.time.LocalTime
import java.util.UUID
import kotlinx.serialization.Serializable

/**
 * Medication inventory row — mirrors iOS `Medication` (Phase2Models).
 *
 * Value type only. Mutated exclusively through [com.lookafter.core.engine.LifeEngine]
 * medication intents.
 */
@Serializable
data class Medication(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val dosage: String = "1 dose",
    /** Wall-clock dose time (time-of-day, not a full timestamp). */
    @Serializable(with = LocalTimeSerializer::class)
    val scheduledTime: LocalTime = LocalTime.of(9, 0),
    val isTaken: Boolean = false,
    @Serializable(with = InstantSerializer::class)
    val lastTakenAt: Instant? = null,
    val adherenceLog: List<@Serializable(with = InstantSerializer::class) Instant> = emptyList(),
) {
    fun markTaken(at: Instant = Instant.now()): Medication = copy(
        isTaken = true,
        lastTakenAt = at,
        adherenceLog = adherenceLog + at,
    )

    fun markUntaken(): Medication = copy(isTaken = false)
}
