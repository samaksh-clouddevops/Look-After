package com.lookafter.app.sync

import android.content.Context
import android.util.Log
import com.lookafter.core.engine.LifeState
import com.lookafter.core.serialization.LookAfterJson
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Multi-device LifeState transport.
 *
 * - [LocalFileSyncTransport]: always available (export/import on device / shared folder)
 * - [FirebaseLifeStateSyncTransport]: reflection-based Firestore push/pull when
 *   Firebase is on the classpath and [google-services.json] is present.
 * - [NoOpSyncTransport]: disabled
 */
interface LifeStateSyncTransport {
    val name: String
    suspend fun push(userId: String, state: LifeState): Result<Unit>
    suspend fun pull(userId: String): Result<LifeState?>
}

class NoOpSyncTransport : LifeStateSyncTransport {
    override val name: String = "none"
    override suspend fun push(userId: String, state: LifeState) = Result.success(Unit)
    override suspend fun pull(userId: String) = Result.success(null)
}

/** Writes snapshots under filesDir/sync for backup / adb pull / future multi-device share. */
class LocalFileSyncTransport(context: Context) : LifeStateSyncTransport {
    private val dir = File(context.applicationContext.filesDir, "sync").also { it.mkdirs() }
    override val name: String = "local-file"

    override suspend fun push(userId: String, state: LifeState): Result<Unit> =
        withContext(Dispatchers.IO) {
            runCatching {
                val file = File(dir, "${userId.sanitize()}.json")
                file.writeText(LookAfterJson.codec.encodeToString(LifeState.serializer(), state))
                Log.i(TAG, "Pushed LifeState → ${file.absolutePath}")
            }
        }

    override suspend fun pull(userId: String): Result<LifeState?> =
        withContext(Dispatchers.IO) {
            runCatching {
                val file = File(dir, "${userId.sanitize()}.json")
                if (!file.exists()) return@runCatching null
                LookAfterJson.codec.decodeFromString(LifeState.serializer(), file.readText())
            }
        }

    private fun String.sanitize(): String = replace(Regex("[^a-zA-Z0-9._-]"), "_")

    companion object {
        private const val TAG = "LocalSync"
    }
}

/**
 * Firestore transport via reflection so the app compiles without google-services.json.
 * Document path: users/{userId}/meta/lifeState  field "json"
 */
class FirebaseLifeStateSyncTransport : LifeStateSyncTransport {
    override val name: String = "firebase"

    override suspend fun push(userId: String, state: LifeState): Result<Unit> =
        withContext(Dispatchers.IO) {
            runCatching {
                val json = LookAfterJson.codec.encodeToString(LifeState.serializer(), state)
                val db = firestore()
                    ?: error("Firestore unavailable — add google-services.json + Firebase deps")
                val doc = db.javaClass
                    .getMethod("collection", String::class.java)
                    .invoke(db, "users")
                val userDoc = doc!!.javaClass.getMethod("document", String::class.java)
                    .invoke(doc, userId)
                val meta = userDoc!!.javaClass.getMethod("collection", String::class.java)
                    .invoke(userDoc, "meta")
                val life = meta!!.javaClass.getMethod("document", String::class.java)
                    .invoke(meta, "lifeState")
                val data = hashMapOf("json" to json, "updatedAt" to System.currentTimeMillis())
                val set = life!!.javaClass.methods.first {
                    it.name == "set" && it.parameterTypes.size >= 1
                }
                val task = set.invoke(life, data)
                awaitTask(task)
                Log.i(TAG, "Firestore push ok user=$userId")
            }.onFailure { Log.w(TAG, "Firestore push failed: ${it.message}") }
        }

    override suspend fun pull(userId: String): Result<LifeState?> =
        withContext(Dispatchers.IO) {
            runCatching {
                val db = firestore() ?: return@runCatching null
                val doc = db.javaClass.getMethod("collection", String::class.java)
                    .invoke(db, "users")
                val userDoc = doc!!.javaClass.getMethod("document", String::class.java)
                    .invoke(doc, userId)
                val meta = userDoc!!.javaClass.getMethod("collection", String::class.java)
                    .invoke(userDoc, "meta")
                val life = meta!!.javaClass.getMethod("document", String::class.java)
                    .invoke(meta, "lifeState")
                val get = life!!.javaClass.getMethod("get")
                val task = get.invoke(life)
                val snap = awaitTask(task) ?: return@runCatching null
                val dataMethod = snap.javaClass.methods.firstOrNull {
                    it.name == "getData" && it.parameterTypes.isEmpty()
                }
                @Suppress("UNCHECKED_CAST")
                val map = dataMethod?.invoke(snap) as? Map<String, Any?>
                val json = map?.get("json") as? String ?: return@runCatching null
                LookAfterJson.codec.decodeFromString(LifeState.serializer(), json)
            }.onFailure { Log.w(TAG, "Firestore pull failed: ${it.message}") }
        }

    private fun firestore(): Any? = runCatching {
        val clazz = Class.forName("com.google.firebase.firestore.FirebaseFirestore")
        clazz.getMethod("getInstance").invoke(null)
    }.getOrNull()

    private fun awaitTask(task: Any?): Any? {
        if (task == null) return null
        // com.google.android.gms.tasks.Tasks.await(task)
        val tasksClazz = Class.forName("com.google.android.gms.tasks.Tasks")
        return tasksClazz.getMethod("await", Class.forName("com.google.android.gms.tasks.Task"))
            .invoke(null, task)
    }

    companion object {
        private const val TAG = "FirebaseSync"

        fun isFirebasePresent(): Boolean =
            runCatching { Class.forName("com.google.firebase.firestore.FirebaseFirestore") }.isSuccess
    }
}

object SyncTransportFactory {
    fun create(context: Context, preferFirebase: Boolean): LifeStateSyncTransport {
        if (preferFirebase && FirebaseLifeStateSyncTransport.isFirebasePresent()) {
            return FirebaseLifeStateSyncTransport()
        }
        return LocalFileSyncTransport(context)
    }
}
