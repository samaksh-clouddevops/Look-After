package com.lookafter.app.webrtc

import android.content.Context
import android.util.Log
import com.lookafter.core.adhd.BodyDoubleSignal
import com.lookafter.core.adhd.BodyDoubleSignalType
import com.lookafter.core.adhd.IceServerConfig
import com.lookafter.core.adhd.WebRtcIceCandidate
import com.lookafter.core.adhd.WebRtcSessionDescription
import com.lookafter.core.serialization.LookAfterJson
import java.time.Instant
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.webrtc.EglBase
import org.webrtc.PeerConnection
import org.webrtc.SurfaceViewRenderer

/**
 * WebRTC peer-connection facade.
 *
 * Prefers [NativeWebRtcSession] when Stream WebRTC is on the classpath;
 * otherwise runs an in-process loopback simulator (CI / failure safe).
 */
class WebRtcPeerController(
    private val context: Context,
    private val ice: IceServerConfig = IceServerConfig(),
    private val localPeerId: String,
    private val enableVideo: Boolean = true,
    private val enableAudio: Boolean = false,
) {
    enum class ConnectionState { NEW, SIGNALING, CONNECTING, CONNECTED, FAILED, CLOSED }
    enum class Backend { NATIVE, SIMULATOR }

    private val _state = MutableStateFlow(ConnectionState.NEW)
    val connectionState: StateFlow<ConnectionState> = _state.asStateFlow()

    private val _backend = MutableStateFlow(Backend.SIMULATOR)
    val backend: StateFlow<Backend> = _backend.asStateFlow()

    private val outbound = CopyOnWriteArrayList<(BodyDoubleSignal) -> Unit>()
    private val json = LookAfterJson.codec
    private var remotePeerId: String? = null
    private var nativeSession: NativeWebRtcSession? = null
    private var pendingLocalRenderer: SurfaceViewRenderer? = null
    private var pendingRemoteRenderer: SurfaceViewRenderer? = null

    val eglContext: EglBase.Context? get() = nativeSession?.eglContext
    val isNative: Boolean get() = nativeSession != null

    fun addOutboundListener(listener: (BodyDoubleSignal) -> Unit) {
        outbound += listener
    }

    fun attachLocalRenderer(renderer: SurfaceViewRenderer) {
        pendingLocalRenderer = renderer
        nativeSession?.attachRenderers(pendingLocalRenderer, pendingRemoteRenderer)
    }

    fun attachRemoteRenderer(renderer: SurfaceViewRenderer) {
        pendingRemoteRenderer = renderer
        nativeSession?.attachRenderers(pendingLocalRenderer, pendingRemoteRenderer)
    }

    fun setLocalVideoEnabled(enabled: Boolean) {
        nativeSession?.setLocalVideoEnabled(enabled)
    }

    fun setLocalAudioEnabled(enabled: Boolean) {
        nativeSession?.setLocalAudioEnabled(enabled)
    }

    /** Re-offer after ICE/PC failure (native restartIce + new offer). */
    fun reconnectAsOfferer(remoteId: String = remotePeerId.orEmpty()) {
        if (remoteId.isBlank()) {
            _state.value = ConnectionState.FAILED
            return
        }
        remotePeerId = remoteId
        _state.value = ConnectionState.SIGNALING
        if (nativeSession != null) {
            runCatching {
                nativeSession!!.restartIce()
                nativeSession!!.startAsOfferer()
            }.onFailure {
                Log.w(TAG, "reconnect failed: ${it.message}")
                fallbackSimulateOffer(remoteId)
            }
        } else {
            startAsOfferer(remoteId)
        }
    }

    fun startAsOfferer(remoteId: String) {
        remotePeerId = remoteId
        _state.value = ConnectionState.SIGNALING
        if (tryStartNative()) {
            runCatching { nativeSession!!.startAsOfferer() }
                .onFailure {
                    Log.w(TAG, "native offer failed: ${it.message}")
                    fallbackSimulateOffer(remoteId)
                }
        } else {
            fallbackSimulateOffer(remoteId)
        }
    }

    fun handleRemoteSignal(signal: BodyDoubleSignal) {
        when (signal.type) {
            BodyDoubleSignalType.OFFER -> handleRemoteOffer(signal)
            BodyDoubleSignalType.ANSWER -> handleRemoteAnswer(signal)
            BodyDoubleSignalType.ICE -> handleRemoteIce(signal)
            BodyDoubleSignalType.HANGUP -> {
                _state.value = ConnectionState.CLOSED
            }
            BodyDoubleSignalType.PRESENCE -> Unit
        }
    }

    fun close() {
        runCatching { nativeSession?.close() }
        nativeSession = null
        pendingLocalRenderer = null
        pendingRemoteRenderer = null
        _state.value = ConnectionState.CLOSED
        emit(
            BodyDoubleSignal(
                type = BodyDoubleSignalType.HANGUP,
                fromPeerId = localPeerId,
                at = Instant.now(),
            ),
        )
    }

    private fun tryStartNative(): Boolean {
        if (!NativeWebRtcSession.isAvailable()) return false
        if (nativeSession != null) return true
        return runCatching {
            nativeSession = NativeWebRtcSession(
                context = context,
                ice = ice,
                enableVideo = enableVideo,
                enableAudio = enableAudio,
                onLocalSdp = { desc ->
                    val type = if (desc.type.equals("answer", true)) {
                        BodyDoubleSignalType.ANSWER
                    } else {
                        BodyDoubleSignalType.OFFER
                    }
                    emitSdp(type, desc)
                    _state.value = ConnectionState.CONNECTING
                },
                onLocalIce = { cand -> emitIce(cand) },
                onConnectionChange = { pcState ->
                    _state.value = when (pcState) {
                        PeerConnection.PeerConnectionState.CONNECTED -> ConnectionState.CONNECTED
                        PeerConnection.PeerConnectionState.CONNECTING,
                        PeerConnection.PeerConnectionState.NEW,
                        -> ConnectionState.CONNECTING
                        PeerConnection.PeerConnectionState.FAILED -> ConnectionState.FAILED
                        PeerConnection.PeerConnectionState.CLOSED,
                        PeerConnection.PeerConnectionState.DISCONNECTED,
                        -> ConnectionState.CLOSED
                    }
                },
                onError = { msg ->
                    Log.w(TAG, msg)
                    _state.value = ConnectionState.FAILED
                },
            )
            nativeSession?.attachRenderers(pendingLocalRenderer, pendingRemoteRenderer)
            _backend.value = Backend.NATIVE
            Log.i(TAG, "Native WebRTC session ready · ICE=${ice.servers.size}")
            true
        }.onFailure {
            Log.w(TAG, "Native WebRTC init failed: ${it.message}")
            nativeSession = null
            _backend.value = Backend.SIMULATOR
        }.getOrDefault(false)
    }

    private fun handleRemoteOffer(signal: BodyDoubleSignal) {
        remotePeerId = signal.fromPeerId
        _state.value = ConnectionState.SIGNALING
        val desc = decodeSdp(signal.payload)
        if (desc != null && tryStartNative()) {
            runCatching { nativeSession!!.handleRemoteOffer(desc) }
                .onFailure {
                    Log.w(TAG, "native handle offer failed: ${it.message}")
                    simulateAnswer(signal.fromPeerId)
                }
        } else {
            simulateAnswer(signal.fromPeerId)
        }
    }

    private fun handleRemoteAnswer(signal: BodyDoubleSignal) {
        val desc = decodeSdp(signal.payload)
        if (desc != null && nativeSession != null) {
            runCatching { nativeSession!!.handleRemoteAnswer(desc) }
        }
        Log.i(TAG, "Got remote answer from ${signal.fromPeerId}")
        if (_state.value != ConnectionState.CONNECTED) {
            _state.value = ConnectionState.CONNECTING
        }
    }

    private fun handleRemoteIce(signal: BodyDoubleSignal) {
        val cand = decodeIce(signal.payload)
        if (cand != null && nativeSession != null) {
            runCatching { nativeSession!!.handleRemoteIce(cand) }
        } else if (_state.value == ConnectionState.CONNECTING && nativeSession == null) {
            _state.value = ConnectionState.CONNECTED
        }
    }

    private fun fallbackSimulateOffer(remoteId: String) {
        _backend.value = Backend.SIMULATOR
        val desc = WebRtcSessionDescription(
            type = "offer",
            sdp = DEMO_SDP,
        )
        emitSdp(BodyDoubleSignalType.OFFER, desc)
        emitIce(WebRtcIceCandidate(candidate = "candidate:1 1 UDP 2122252543 127.0.0.1 54321 typ host"))
        _state.value = ConnectionState.CONNECTING
        Log.i(TAG, "Simulator offer → $remoteId · ICE=${ice.servers.map { it.urls }}")
    }

    private fun simulateAnswer(from: String) {
        _backend.value = Backend.SIMULATOR
        emitSdp(
            BodyDoubleSignalType.ANSWER,
            WebRtcSessionDescription(type = "answer", sdp = DEMO_SDP),
        )
        emitIce(WebRtcIceCandidate(candidate = "candidate:2 1 UDP 2122252542 127.0.0.1 54322 typ host"))
        _state.value = ConnectionState.CONNECTED
        Log.i(TAG, "Simulator answer ← $from")
    }

    private fun decodeSdp(payload: String): WebRtcSessionDescription? = runCatching {
        json.decodeFromString(WebRtcSessionDescription.serializer(), payload)
    }.getOrNull()

    private fun decodeIce(payload: String): WebRtcIceCandidate? = runCatching {
        val pure = payload.substringBefore("|to=")
        json.decodeFromString(WebRtcIceCandidate.serializer(), pure)
    }.getOrNull()

    private fun emitSdp(type: BodyDoubleSignalType, desc: WebRtcSessionDescription) {
        emit(
            BodyDoubleSignal(
                type = type,
                fromPeerId = localPeerId,
                payload = json.encodeToString(WebRtcSessionDescription.serializer(), desc),
                at = Instant.now(),
            ),
        )
    }

    private fun emitIce(cand: WebRtcIceCandidate) {
        val to = remotePeerId.orEmpty()
        emit(
            BodyDoubleSignal(
                type = BodyDoubleSignalType.ICE,
                fromPeerId = localPeerId,
                payload = json.encodeToString(WebRtcIceCandidate.serializer(), cand) + "|to=$to",
                at = Instant.now(),
            ),
        )
    }

    private fun emit(signal: BodyDoubleSignal) {
        outbound.forEach { runCatching { it(signal) } }
    }

    companion object {
        private const val TAG = "WebRtcPeer"
        private const val DEMO_SDP =
            "v=0\r\no=- 0 0 IN IP4 127.0.0.1\r\ns=LookAfterDemo\r\nt=0 0\r\n" +
                "a=ice-options:trickle\r\nm=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\n"
    }
}
