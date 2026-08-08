package com.lookafter.core.adhd

import kotlinx.serialization.Serializable

/**
 * ICE / STUN / TURN configuration for WebRTC body-double sessions.
 * Defaults include public Google STUNs; TURN is optional (paid relays).
 */
@Serializable
data class IceServer(
    val urls: List<String>,
    val username: String = "",
    val credential: String = "",
) {
    constructor(url: String, username: String = "", credential: String = "") :
        this(listOf(url), username, credential)
}

@Serializable
data class IceServerConfig(
    val servers: List<IceServer> = defaultServers(),
    /** Prefer TURN relay when true (stricter NATs; costs bandwidth on TURN host). */
    val iceTransportPolicy: IceTransportPolicy = IceTransportPolicy.ALL,
) {
    enum class IceTransportPolicy { ALL, RELAY }

    companion object {
        fun defaultServers(): List<IceServer> = listOf(
            IceServer("stun:stun.l.google.com:19302"),
            IceServer("stun:stun1.l.google.com:19302"),
            IceServer("stun:stun2.l.google.com:19302"),
        )

        /**
         * Build from optional TURN triple (url, user, pass).
         * Empty turnUrl → STUN-only defaults.
         */
        fun fromTurn(
            turnUrl: String?,
            turnUser: String? = null,
            turnPass: String? = null,
            forceRelay: Boolean = false,
        ): IceServerConfig {
            val base = defaultServers().toMutableList()
            val url = turnUrl?.trim().orEmpty()
            if (url.isNotEmpty()) {
                base += IceServer(
                    urls = listOf(url),
                    username = turnUser.orEmpty(),
                    credential = turnPass.orEmpty(),
                )
            }
            return IceServerConfig(
                servers = base,
                iceTransportPolicy = if (forceRelay) IceTransportPolicy.RELAY else IceTransportPolicy.ALL,
            )
        }
    }
}

/** SDP + ICE blobs exchanged over [BodyDoubleSignal]. */
@Serializable
data class WebRtcSessionDescription(
    val type: String, // offer | answer
    val sdp: String,
)

@Serializable
data class WebRtcIceCandidate(
    val sdpMid: String = "0",
    val sdpMLineIndex: Int = 0,
    val candidate: String,
)
