package com.lookafter.core.adhd

import com.lookafter.core.serialization.InstantSerializer
import java.time.Duration
import java.time.Instant
import kotlinx.serialization.Serializable

/** End-of-session summary for body-double rooms (Phase C3). */
@Serializable
data class BodyDoubleSessionSummary(
    val roomId: String = "",
    @Serializable(with = InstantSerializer::class)
    val startedAt: Instant = Instant.EPOCH,
    @Serializable(with = InstantSerializer::class)
    val endedAt: Instant = Instant.EPOCH,
    val durationSeconds: Long = 0,
    val peerCount: Int = 0,
    val peerNames: List<String> = emptyList(),
    val webRtcBackend: String = "simulator",
    val signaling: String = "local-file",
    val reachedConnected: Boolean = false,
    val focusStarted: Boolean = false,
    val leftReason: String = "leave",
) {
    val durationLabel: String
        get() {
            val m = durationSeconds / 60
            val s = durationSeconds % 60
            return if (m > 0) "${m}m ${s}s" else "${s}s"
        }

    companion object {
        fun fromSession(
            roomId: String,
            startedAt: Instant,
            endedAt: Instant = Instant.now(),
            peers: List<BodyDoublePeer>,
            webRtcBackend: String,
            signaling: String,
            reachedConnected: Boolean,
            focusStarted: Boolean,
            leftReason: String = "leave",
        ): BodyDoubleSessionSummary {
            val secs = Duration.between(startedAt, endedAt).seconds.coerceAtLeast(0)
            return BodyDoubleSessionSummary(
                roomId = roomId,
                startedAt = startedAt,
                endedAt = endedAt,
                durationSeconds = secs,
                peerCount = peers.size,
                peerNames = peers.map { it.displayName }.filter { it.isNotBlank() },
                webRtcBackend = webRtcBackend,
                signaling = signaling,
                reachedConnected = reachedConnected,
                focusStarted = focusStarted,
                leftReason = leftReason,
            )
        }
    }
}
