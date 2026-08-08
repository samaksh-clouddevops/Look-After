package com.lookafter.core.adhd

import com.lookafter.core.serialization.InstantSerializer
import java.time.Instant
import java.util.UUID
import kotlinx.serialization.Serializable

@Serializable
enum class BodyDoubleRoomPhase {
    IDLE,
    CREATING,
    WAITING,
    CONNECTING,
    CONNECTED,
    RECONNECTING,
    ENDED,
    FAILED,
}

@Serializable
enum class BodyDoubleSignalType {
    OFFER,
    ANSWER,
    ICE,
    HANGUP,
    PRESENCE,
}

@Serializable
data class BodyDoubleSignal(
    val type: BodyDoubleSignalType,
    val fromPeerId: String,
    val payload: String = "",
    @Serializable(with = InstantSerializer::class)
    val at: Instant = Instant.EPOCH,
)

@Serializable
data class BodyDoublePeer(
    val id: String,
    val displayName: String = "Partner",
    val isLocal: Boolean = false,
    val isConnected: Boolean = false,
)

@Serializable
data class BodyDoubleRoomState(
    val roomId: String? = null,
    val localPeerId: String = "",
    val phase: BodyDoubleRoomPhase = BodyDoubleRoomPhase.IDLE,
    val peers: List<BodyDoublePeer> = emptyList(),
    val signals: List<BodyDoubleSignal> = emptyList(),
    val lastError: String? = null,
    val useCamera: Boolean = true,
    val useMicrophone: Boolean = false,
) {
    val isActive: Boolean
        get() = phase != BodyDoubleRoomPhase.IDLE && phase != BodyDoubleRoomPhase.ENDED

    val remotePeers: List<BodyDoublePeer>
        get() = peers.filterNot { it.isLocal }
}

sealed class BodyDoubleRoomIntent {
    data class Create(
        val displayName: String = "You",
        val useCamera: Boolean = true,
        val useMicrophone: Boolean = false,
        val now: Instant = Instant.now(),
    ) : BodyDoubleRoomIntent()

    data class Join(
        val roomId: String,
        val displayName: String = "You",
        val useCamera: Boolean = true,
        val useMicrophone: Boolean = false,
        val now: Instant = Instant.now(),
    ) : BodyDoubleRoomIntent()

    data class PeerJoined(val peer: BodyDoublePeer) : BodyDoubleRoomIntent()
    data class PeerLeft(val peerId: String) : BodyDoubleRoomIntent()
    data class SignalReceived(val signal: BodyDoubleSignal) : BodyDoubleRoomIntent()
    data class MarkConnected(val peerId: String) : BodyDoubleRoomIntent()
    data class Fail(val message: String) : BodyDoubleRoomIntent()
    data object Leave : BodyDoubleRoomIntent()
}

/**
 * Pure WebRTC room state machine.
 * Signaling transport is injected at the app layer (local loopback demo or Firebase).
 */
object BodyDoubleRoomEngine {

    fun reduce(current: BodyDoubleRoomState, intent: BodyDoubleRoomIntent): BodyDoubleRoomState =
        when (intent) {
            is BodyDoubleRoomIntent.Create -> {
                val localId = "local-" + UUID.randomUUID().toString().take(8)
                val roomId = "room-" + UUID.randomUUID().toString().take(6)
                BodyDoubleRoomState(
                    roomId = roomId,
                    localPeerId = localId,
                    phase = BodyDoubleRoomPhase.WAITING,
                    peers = listOf(
                        BodyDoublePeer(
                            id = localId,
                            displayName = intent.displayName,
                            isLocal = true,
                            isConnected = true,
                        ),
                    ),
                    useCamera = intent.useCamera,
                    useMicrophone = intent.useMicrophone,
                )
            }
            is BodyDoubleRoomIntent.Join -> {
                val localId = "local-" + UUID.randomUUID().toString().take(8)
                val room = intent.roomId.trim().ifEmpty { return current.copy(lastError = "Room code required") }
                BodyDoubleRoomState(
                    roomId = room,
                    localPeerId = localId,
                    phase = BodyDoubleRoomPhase.CONNECTING,
                    peers = listOf(
                        BodyDoublePeer(
                            id = localId,
                            displayName = intent.displayName,
                            isLocal = true,
                            isConnected = true,
                        ),
                        BodyDoublePeer(id = "remote-pending", displayName = "Partner"),
                    ),
                    useCamera = intent.useCamera,
                    useMicrophone = intent.useMicrophone,
                )
            }
            is BodyDoubleRoomIntent.PeerJoined -> {
                val without = current.peers.filterNot { it.id == intent.peer.id || it.id == "remote-pending" }
                current.copy(
                    peers = without + intent.peer,
                    phase = if (current.phase == BodyDoubleRoomPhase.WAITING) {
                        BodyDoubleRoomPhase.CONNECTING
                    } else {
                        current.phase
                    },
                )
            }
            is BodyDoubleRoomIntent.PeerLeft -> current.copy(
                peers = current.peers.filterNot { it.id == intent.peerId },
                phase = if (current.remotePeers.none { it.id != intent.peerId }) {
                    BodyDoubleRoomPhase.WAITING
                } else {
                    current.phase
                },
            )
            is BodyDoubleRoomIntent.SignalReceived -> current.copy(
                signals = (current.signals + intent.signal).takeLast(50),
                phase = when (intent.signal.type) {
                    BodyDoubleSignalType.OFFER, BodyDoubleSignalType.ANSWER ->
                        BodyDoubleRoomPhase.CONNECTING
                    BodyDoubleSignalType.HANGUP -> BodyDoubleRoomPhase.ENDED
                    else -> current.phase
                },
            )
            is BodyDoubleRoomIntent.MarkConnected -> current.copy(
                peers = current.peers.map {
                    if (it.id == intent.peerId) it.copy(isConnected = true) else it
                },
                phase = BodyDoubleRoomPhase.CONNECTED,
            )
            is BodyDoubleRoomIntent.Fail -> current.copy(
                phase = BodyDoubleRoomPhase.FAILED,
                lastError = intent.message,
            )
            BodyDoubleRoomIntent.Leave -> BodyDoubleRoomState(
                phase = BodyDoubleRoomPhase.ENDED,
                lastError = current.lastError,
            )
        }

    /** Local demo: invent a remote peer + answer after create (no network). */
    fun demoConnect(current: BodyDoubleRoomState, now: Instant = Instant.now()): BodyDoubleRoomState {
        if (current.roomId == null) return current
        val remote = BodyDoublePeer(id = "demo-remote", displayName = "Body double", isConnected = true)
        var next = reduce(current, BodyDoubleRoomIntent.PeerJoined(remote))
        next = reduce(
            next,
            BodyDoubleRoomIntent.SignalReceived(
                BodyDoubleSignal(
                    type = BodyDoubleSignalType.ANSWER,
                    fromPeerId = remote.id,
                    payload = "demo-sdp",
                    at = now,
                ),
            ),
        )
        return reduce(next, BodyDoubleRoomIntent.MarkConnected(remote.id))
    }
}
