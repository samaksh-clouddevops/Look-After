package com.lookafter.app.webrtc

import android.content.Context
import android.util.Log
import com.lookafter.core.adhd.BodyDoubleSignal
import com.lookafter.core.adhd.RoomPresence
import com.lookafter.core.adhd.RoomSignalEnvelope

interface RoomSignalingTransport {
    val name: String
    fun join(roomId: String, presence: RoomPresence)
    fun publish(signal: BodyDoubleSignal)
    fun leave(peerId: String)
    fun addListener(listener: (RoomSignalEnvelope) -> Unit)
    fun removeListener(listener: (RoomSignalEnvelope) -> Unit)
    fun close()
}

object RoomSignalingFactory {
    fun create(context: Context, preferFirestore: Boolean = true): RoomSignalingTransport {
        if (preferFirestore) {
            val fs = FirestoreRoomSignaling()
            if (fs.isAvailable()) {
                Log.i("RoomSignal", "Using Firestore room signaling")
                return fs
            }
        }
        Log.i("RoomSignal", "Using local-file room signaling")
        return LocalFileRoomSignaling(context)
    }
}
