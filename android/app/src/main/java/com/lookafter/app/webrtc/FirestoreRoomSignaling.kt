package com.lookafter.app.webrtc

import android.util.Log
import com.lookafter.core.adhd.BodyDoubleSignal
import com.lookafter.core.adhd.RoomPresence
import com.lookafter.core.adhd.RoomSignalCodec
import com.lookafter.core.adhd.RoomSignalEnvelope
import java.time.Instant
import java.util.concurrent.CopyOnWriteArrayList

class FirestoreRoomSignaling : RoomSignalingTransport {
    override val name: String = "firestore"
    private val listeners = CopyOnWriteArrayList<(RoomSignalEnvelope) -> Unit>()
    private var roomId: String? = null
    private var selfPeerId: String = ""
    private var registration: Any? = null
    private val available: Boolean =
        runCatching { Class.forName("com.google.firebase.firestore.FirebaseFirestore") }.isSuccess

    fun isAvailable(): Boolean = available

    override fun join(roomId: String, presence: RoomPresence) {
        if (!available) return
        this.roomId = roomId
        selfPeerId = presence.peerId
        runCatching {
            val doc = docRef(firestore(), roomId)
            val listener = java.lang.reflect.Proxy.newProxyInstance(
                doc.javaClass.classLoader,
                arrayOf(Class.forName("com.google.firebase.firestore.EventListener")),
            ) { _, method, args ->
                if (method.name == "onEvent" && args != null && args.isNotEmpty() && args[0] != null) {
                    val snap = args[0]
                    val data = snap.javaClass.getMethod("getData").invoke(snap) as? Map<*, *>
                    val raw = data?.get("envelope") as? String
                    if (raw != null) RoomSignalCodec.decode(raw)?.let { emit(it) }
                }
                null
            }
            registration = doc.javaClass.methods
                .first { it.name == "addSnapshotListener" && it.parameterTypes.size == 1 }
                .invoke(doc, listener)
            mutate(roomId) { RoomSignalCodec.upsertPresence(it, presence) }
        }.onFailure { Log.w("FirestoreRoomSignal", "join failed: ${it.message}") }
    }

    override fun publish(signal: BodyDoubleSignal) {
        val id = roomId ?: return
        if (available) mutate(id) { RoomSignalCodec.appendSignal(it, signal) }
    }

    override fun leave(peerId: String) {
        val id = roomId ?: return
        if (available) mutate(id) { RoomSignalCodec.markLeft(it, peerId) }
        runCatching {
            registration?.javaClass?.methods
                ?.firstOrNull { it.name == "remove" && it.parameterTypes.isEmpty() }
                ?.invoke(registration)
        }
        registration = null
    }

    override fun addListener(listener: (RoomSignalEnvelope) -> Unit) { listeners += listener }
    override fun removeListener(listener: (RoomSignalEnvelope) -> Unit) { listeners -= listener }
    override fun close() {
        if (selfPeerId.isNotBlank()) leave(selfPeerId)
        listeners.clear()
        roomId = null
    }

    private fun mutate(roomId: String, transform: (RoomSignalEnvelope) -> RoomSignalEnvelope) {
        runCatching {
            val doc = docRef(firestore(), roomId)
            val tasksClass = Class.forName("com.google.android.gms.tasks.Tasks")
            val taskClass = Class.forName("com.google.android.gms.tasks.Task")
            val getTask = doc.javaClass.getMethod("get").invoke(doc)
            val snap = tasksClass.getMethod("await", taskClass).invoke(null, getTask)
            val data = snap?.javaClass?.getMethod("getData")?.invoke(snap) as? Map<*, *>
            val raw = data?.get("envelope") as? String
            val current = raw?.let { RoomSignalCodec.decode(it) } ?: RoomSignalEnvelope.empty(roomId)
            val next = transform(current)
            val payload = hashMapOf(
                "envelope" to RoomSignalCodec.encode(next),
                "updatedAt" to Instant.now().toString(),
            )
            val setTask = doc.javaClass.methods
                .first { it.name == "set" && it.parameterTypes.size == 1 }
                .invoke(doc, payload)
            tasksClass.getMethod("await", taskClass).invoke(null, setTask)
            emit(next)
        }.onFailure { Log.w("FirestoreRoomSignal", "mutate failed: ${it.message}") }
    }

    private fun emit(envelope: RoomSignalEnvelope) {
        listeners.forEach { runCatching { it(envelope) } }
    }

    private fun firestore(): Any =
        Class.forName("com.google.firebase.firestore.FirebaseFirestore")
            .getMethod("getInstance").invoke(null)

    private fun docRef(db: Any, roomId: String): Any {
        val col = db.javaClass.getMethod("collection", String::class.java)
            .invoke(db, "lookafter_rooms")
        return col.javaClass.getMethod("document", String::class.java).invoke(col, roomId)
    }
}
