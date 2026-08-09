package com.lookafter.core.adhd

import com.lookafter.core.serialization.InstantSerializer
import com.lookafter.core.serialization.LookAfterJson
import java.time.Instant
import kotlinx.serialization.Serializable

/** Wire format for multi-device body-double room signaling (C2). */
@Serializable
data class RoomPresence(
    val peerId: String,
    val displayName: String = "Partner",
    @Serializable(with = InstantSerializer::class)
    val joinedAt: Instant = Instant.EPOCH,
    val left: Boolean = false,
)

@Serializable
data class RoomSignalEnvelope(
    val roomId: String,
    val signals: List<BodyDoubleSignal> = emptyList(),
    val presence: List<RoomPresence> = emptyList(),
    @Serializable(with = InstantSerializer::class)
    val updatedAt: Instant = Instant.EPOCH,
) {
    companion object {
        fun empty(roomId: String) = RoomSignalEnvelope(roomId = roomId)
    }
}

object RoomSignalCodec {
    private val json = LookAfterJson.codec

    fun encode(envelope: RoomSignalEnvelope): String =
        json.encodeToString(RoomSignalEnvelope.serializer(), envelope)

    fun decode(raw: String): RoomSignalEnvelope? = runCatching {
        json.decodeFromString(RoomSignalEnvelope.serializer(), raw.trim())
    }.getOrNull()

    fun appendSignal(
        current: RoomSignalEnvelope,
        signal: BodyDoubleSignal,
        maxSignals: Int = 80,
    ): RoomSignalEnvelope = current.copy(
        signals = (current.signals + signal).takeLast(maxSignals),
        updatedAt = Instant.now(),
    )

    fun upsertPresence(
        current: RoomSignalEnvelope,
        presence: RoomPresence,
    ): RoomSignalEnvelope {
        val without = current.presence.filterNot { it.peerId == presence.peerId }
        return current.copy(
            presence = without + presence,
            updatedAt = Instant.now(),
        )
    }

    fun markLeft(current: RoomSignalEnvelope, peerId: String): RoomSignalEnvelope {
        val presence = current.presence.map {
            if (it.peerId == peerId) it.copy(left = true) else it
        }
        val hangup = BodyDoubleSignal(
            type = BodyDoubleSignalType.HANGUP,
            fromPeerId = peerId,
            at = Instant.now(),
        )
        return current.copy(
            presence = presence,
            signals = (current.signals + hangup).takeLast(80),
            updatedAt = Instant.now(),
        )
    }
}
