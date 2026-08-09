package com.lookafter.app.webrtc

import android.content.Context
import android.util.Log
import com.lookafter.core.adhd.IceServerConfig
import com.lookafter.core.adhd.WebRtcIceCandidate
import com.lookafter.core.adhd.WebRtcSessionDescription
import org.webrtc.AudioSource
import org.webrtc.AudioTrack
import org.webrtc.Camera2Enumerator
import org.webrtc.CameraEnumerator
import org.webrtc.DataChannel
import org.webrtc.DefaultVideoDecoderFactory
import org.webrtc.DefaultVideoEncoderFactory
import org.webrtc.EglBase
import org.webrtc.IceCandidate
import org.webrtc.MediaConstraints
import org.webrtc.MediaStream
import org.webrtc.PeerConnection
import org.webrtc.PeerConnectionFactory
import org.webrtc.RtpReceiver
import org.webrtc.SdpObserver
import org.webrtc.SessionDescription
import org.webrtc.SurfaceTextureHelper
import org.webrtc.SurfaceViewRenderer
import org.webrtc.VideoCapturer
import org.webrtc.VideoSource
import org.webrtc.VideoTrack

/**
 * Real [org.webrtc] peer session for body-double media.
 * Owns PeerConnectionFactory, local camera/mic tracks, and remote video sink.
 */
class NativeWebRtcSession(
    context: Context,
    private val ice: IceServerConfig,
    private val enableVideo: Boolean = true,
    private val enableAudio: Boolean = false,
    private val onLocalSdp: (WebRtcSessionDescription) -> Unit,
    private val onLocalIce: (WebRtcIceCandidate) -> Unit,
    private val onConnectionChange: (PeerConnection.PeerConnectionState) -> Unit,
    private val onError: (String) -> Unit,
) {
    private val appContext = context.applicationContext
    private val eglBase: EglBase = EglBase.create()
    private val factory: PeerConnectionFactory
    private var peerConnection: PeerConnection? = null
    private var videoCapturer: VideoCapturer? = null
    private var surfaceHelper: SurfaceTextureHelper? = null
    private var localVideoSource: VideoSource? = null
    private var localAudioSource: AudioSource? = null
    private var localVideoTrack: VideoTrack? = null
    private var localAudioTrack: AudioTrack? = null
    private var localRenderer: SurfaceViewRenderer? = null
    private var remoteRenderer: SurfaceViewRenderer? = null

    val eglContext: EglBase.Context get() = eglBase.eglBaseContext
    val isAlive: Boolean get() = peerConnection != null

    init {
        ensureFactoryInitialized(appContext)
        val encoder = DefaultVideoEncoderFactory(eglBase.eglBaseContext, true, true)
        val decoder = DefaultVideoDecoderFactory(eglBase.eglBaseContext)
        factory = PeerConnectionFactory.builder()
            .setVideoEncoderFactory(encoder)
            .setVideoDecoderFactory(decoder)
            .createPeerConnectionFactory()
    }

    /**
     * Bind already-initialized compose [SurfaceViewRenderer]s.
     * Callers (Compose) own init/release; we only attach tracks.
     */
    fun attachRenderers(local: SurfaceViewRenderer?, remote: SurfaceViewRenderer?) {
        localRenderer = local
        remoteRenderer = remote
        local?.setMirror(true)
        localVideoTrack?.let { track ->
            local?.let { track.addSink(it) }
        }
    }

    fun startAsOfferer() {
        ensurePeer()
        val constraints = MediaConstraints().apply {
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveVideo", "true"))
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveAudio", enableAudio.toString()))
        }
        peerConnection?.createOffer(sdpObserver { sdp ->
            peerConnection?.setLocalDescription(simpleSdpObserver, sdp)
            onLocalSdp(WebRtcSessionDescription(type = sdp.type.canonicalForm(), sdp = sdp.description))
        }, constraints)
    }

    fun handleRemoteOffer(desc: WebRtcSessionDescription) {
        ensurePeer()
        val remote = SessionDescription(SessionDescription.Type.OFFER, desc.sdp)
        peerConnection?.setRemoteDescription(simpleSdpObserver, remote)
        val constraints = MediaConstraints().apply {
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveVideo", "true"))
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveAudio", enableAudio.toString()))
        }
        peerConnection?.createAnswer(sdpObserver { sdp ->
            peerConnection?.setLocalDescription(simpleSdpObserver, sdp)
            onLocalSdp(WebRtcSessionDescription(type = sdp.type.canonicalForm(), sdp = sdp.description))
        }, constraints)
    }

    fun handleRemoteAnswer(desc: WebRtcSessionDescription) {
        peerConnection?.setRemoteDescription(
            simpleSdpObserver,
            SessionDescription(SessionDescription.Type.ANSWER, desc.sdp),
        )
    }

    fun handleRemoteIce(cand: WebRtcIceCandidate) {
        peerConnection?.addIceCandidate(
            IceCandidate(cand.sdpMid, cand.sdpMLineIndex, cand.candidate),
        )
    }

    fun close() {
        runCatching { videoCapturer?.stopCapture() }
        videoCapturer?.dispose()
        videoCapturer = null
        surfaceHelper?.dispose()
        surfaceHelper = null
        localVideoTrack?.removeSink(localRenderer)
        localVideoTrack?.dispose()
        localAudioTrack?.dispose()
        localVideoSource?.dispose()
        localAudioSource?.dispose()
        localVideoTrack = null
        localAudioTrack = null
        localVideoSource = null
        localAudioSource = null
        peerConnection?.close()
        peerConnection?.dispose()
        peerConnection = null
        // Compose owns SurfaceViewRenderer lifecycle — only detach references.
        localRenderer = null
        remoteRenderer = null
        runCatching { factory.dispose() }
        runCatching { eglBase.release() }
    }

    private fun ensurePeer() {
        if (peerConnection != null) return
        val rtcConfig = PeerConnection.RTCConfiguration(iceServers()).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
            continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_CONTINUALLY
            if (ice.iceTransportPolicy == IceServerConfig.IceTransportPolicy.RELAY) {
                iceTransportsType = PeerConnection.IceTransportsType.RELAY
            }
        }
        peerConnection = factory.createPeerConnection(rtcConfig, pcObserver)
            ?: error("createPeerConnection returned null")
        addLocalTracks()
    }

    private fun addLocalTracks() {
        if (enableAudio) {
            localAudioSource = factory.createAudioSource(MediaConstraints())
            localAudioTrack = factory.createAudioTrack("AUDIO", localAudioSource)
            peerConnection?.addTrack(localAudioTrack, listOf("ARDAMS"))
        }
        if (!enableVideo) return
        val capturer = createCameraCapturer() ?: run {
            onError("No front camera for WebRTC")
            return
        }
        videoCapturer = capturer
        surfaceHelper = SurfaceTextureHelper.create("CaptureThread", eglBase.eglBaseContext)
        localVideoSource = factory.createVideoSource(capturer.isScreencast)
        capturer.initialize(surfaceHelper, appContext, localVideoSource!!.capturerObserver)
        capturer.startCapture(640, 480, 24)
        localVideoTrack = factory.createVideoTrack("VIDEO", localVideoSource)
        localRenderer?.let { localVideoTrack?.addSink(it) }
        peerConnection?.addTrack(localVideoTrack, listOf("ARDAMS"))
    }

    private fun createCameraCapturer(): VideoCapturer? {
        val enumerator: CameraEnumerator = Camera2Enumerator(appContext)
        val front = enumerator.deviceNames.firstOrNull { enumerator.isFrontFacing(it) }
            ?: enumerator.deviceNames.firstOrNull()
            ?: return null
        return enumerator.createCapturer(front, null)
    }

    private fun iceServers(): List<PeerConnection.IceServer> =
        ice.servers.map { server ->
            val builder = PeerConnection.IceServer.builder(server.urls)
            if (server.username.isNotBlank()) {
                builder.setUsername(server.username)
                builder.setPassword(server.credential)
            }
            builder.createIceServer()
        }

    private val simpleSdpObserver = object : SdpObserver {
        override fun onCreateSuccess(p0: SessionDescription?) = Unit
        override fun onSetSuccess() = Unit
        override fun onCreateFailure(p0: String?) = onError(p0 ?: "sdp create fail")
        override fun onSetFailure(p0: String?) = onError(p0 ?: "sdp set fail")
    }

    private fun sdpObserver(onSuccess: (SessionDescription) -> Unit) = object : SdpObserver {
        override fun onCreateSuccess(sdp: SessionDescription?) {
            if (sdp != null) onSuccess(sdp) else onError("null sdp")
        }
        override fun onSetSuccess() = Unit
        override fun onCreateFailure(error: String?) = onError(error ?: "createOffer/Answer failed")
        override fun onSetFailure(error: String?) = onError(error ?: "setLocal/Remote failed")
    }

    private val pcObserver = object : PeerConnection.Observer {
        override fun onSignalingChange(state: PeerConnection.SignalingState?) = Unit
        override fun onIceConnectionChange(state: PeerConnection.IceConnectionState?) = Unit
        override fun onIceConnectionReceivingChange(p0: Boolean) = Unit
        override fun onIceGatheringChange(p0: PeerConnection.IceGatheringState?) = Unit
        override fun onIceCandidate(candidate: IceCandidate?) {
            candidate ?: return
            onLocalIce(
                WebRtcIceCandidate(
                    sdpMid = candidate.sdpMid ?: "0",
                    sdpMLineIndex = candidate.sdpMLineIndex,
                    candidate = candidate.sdp,
                ),
            )
        }
        override fun onIceCandidatesRemoved(p0: Array<out IceCandidate>?) = Unit
        override fun onAddStream(p0: MediaStream?) = Unit
        override fun onRemoveStream(p0: MediaStream?) = Unit
        override fun onDataChannel(p0: DataChannel?) = Unit
        override fun onRenegotiationNeeded() = Unit
        override fun onAddTrack(receiver: RtpReceiver?, streams: Array<out MediaStream>?) {
            val track = receiver?.track() as? VideoTrack ?: return
            remoteRenderer?.let { track.addSink(it) }
        }
        override fun onConnectionChange(newState: PeerConnection.PeerConnectionState?) {
            Log.i(TAG, "PC state=$newState")
            if (newState != null) onConnectionChange(newState)
        }
    }

    companion object {
        private const val TAG = "NativeWebRtc"
        @Volatile private var factoryInitialized = false

        fun isAvailable(): Boolean =
            runCatching { Class.forName("org.webrtc.PeerConnectionFactory") }.isSuccess

        private fun ensureFactoryInitialized(context: Context) {
            if (factoryInitialized) return
            synchronized(this) {
                if (factoryInitialized) return
                PeerConnectionFactory.initialize(
                    PeerConnectionFactory.InitializationOptions.builder(context)
                        .setEnableInternalTracer(false)
                        .createInitializationOptions(),
                )
                factoryInitialized = true
            }
        }
    }
}
