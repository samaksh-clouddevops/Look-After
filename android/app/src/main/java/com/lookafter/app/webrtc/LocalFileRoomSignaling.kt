package com.lookafter.app.webrtc

import android.content.Context
import com.lookafter.core.adhd.BodyDoubleSignal
import com.lookafter.core.adhd.RoomPresence
import com.lookafter.core.adhd.RoomSignalCodec
import com.lookafter.core.adhd.RoomSignalEnvelope
import java.io.File
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.flow.MutableStateFlow

/** File-polled room signaling under app filesDir/webrtc-rooms/. */
class LocalFileRoomSignaling(
    context: Context,
) : RoomSignalingTransport {

    override val name: String = "local-file"

    private val dir = File(context.applicationContext.filesDir, "webrtc-rooms").also { it.mkdirs() }
    private val listeners = CopyOnWriteArrayList<(RoomSignalEnvelope) -> Unit>()
    private val roomId = MutableStateFlow<String?>(null)
    private var lastRaw: String = ""
    private val running = AtomicBoolean(false)
    private val executor = Executors.newSingleThreadScheduledExecutor()
    private var pollTask: ScheduledFuture<*>? = null

    override fun join(roomId: String, presence: RoomPresence) {
        this.roomId.value = roomId
        running.set(true)
        synchronized(dir) {
            val current = readEnvelope(roomId) ?: RoomSignalEnvelope.empty(roomId)
            val next = RoomSignalCodec.upsertPresence(current, presence)
            writeEnvelope(next)
            lastRaw = RoomSignalCodec.encode(next)
            emit(next)
        }
        pollTask?.cancel(false)
        pollTask = executor.scheduleWithFixedDelay({ poll() }, 400, 400, TimeUnit.MILLISECONDS)
    }

    override fun publish(signal: BodyDoubleSignal) {
        val id = roomId.value ?: return
        synchronized(dir) {
            val current = readEnvelope(id) ?: RoomSignalEnvelope.empty(id)
            val next = RoomSignalCodec.appendSignal(current, signal)
            writeEnvelope(next)
            lastRaw = RoomSignalCodec.encode(next)
            emit(next)
        }
    }

    override fun leave(peerId: String) {
        val id = roomId.value ?: return
        synchronized(dir) {
            val current = readEnvelope(id) ?: return
            writeEnvelope(RoomSignalCodec.markLeft(current, peerId))
        }
        running.set(false)
        pollTask?.cancel(false)
        pollTask = null
    }

    override fun addListener(listener: (RoomSignalEnvelope) -> Unit) {
        listeners += listener
    }

    override fun removeListener(listener: (RoomSignalEnvelope) -> Unit) {
        listeners -= listener
    }

    override fun close() {
        running.set(false)
        pollTask?.cancel(false)
        pollTask = null
        listeners.clear()
        roomId.value = null
    }

    private fun poll() {
        if (!running.get()) return
        val id = roomId.value ?: return
        val env = readEnvelope(id) ?: return
        val raw = RoomSignalCodec.encode(env)
        if (raw != lastRaw) {
            lastRaw = raw
            emit(env)
        }
    }

    private fun emit(envelope: RoomSignalEnvelope) {
        listeners.forEach { runCatching { it(envelope) } }
    }

    private fun fileFor(roomId: String): File =
        File(dir, roomId.replace(Regex("[^a-zA-Z0-9_-]"), "_") + ".json")

    private fun readEnvelope(roomId: String): RoomSignalEnvelope? = runCatching {
        val f = fileFor(roomId)
        if (!f.exists()) return null
        RoomSignalCodec.decode(f.readText(Charsets.UTF_8))
    }.getOrNull()

    private fun writeEnvelope(envelope: RoomSignalEnvelope) {
        fileFor(envelope.roomId).writeText(RoomSignalCodec.encode(envelope), Charsets.UTF_8)
    }
}
