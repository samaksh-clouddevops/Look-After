package com.lookafter.app.data

import android.content.Context
import android.util.Log
import androidx.datastore.core.CorruptionException
import androidx.datastore.core.DataStore
import androidx.datastore.core.Serializer
import androidx.datastore.dataStore
import com.lookafter.core.engine.LifeState
import com.lookafter.core.engine.LifeStateRepository
import com.lookafter.core.serialization.LookAfterJson
import java.io.InputStream
import java.io.OutputStream
import kotlinx.coroutines.flow.first
import kotlinx.serialization.SerializationException

private const val TAG = "LifeStateStore"
private const val DATA_STORE_FILE = "life_state.json"

/**
 * DataStore-backed [LifeStateRepository].
 *
 * Writes a full JSON snapshot of [LifeState] on every save — atomic file
 * replace semantics via DataStore (mirrors iOS atomic JSON file writes).
 */
class DataStoreLifeStateRepository(
    private val dataStore: DataStore<LifeState>,
) : LifeStateRepository {

    override suspend fun load(): LifeState? {
        return try {
            val loaded = dataStore.data.first()
            // EMPTY is the Serializer default when the file is absent — treat as null
            // so LifeEngine can inject the first-launch seed / fallback.
            if (loaded == LifeState.EMPTY) null else loaded
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to load LifeState snapshot", t)
            null
        }
    }

    override suspend fun save(state: LifeState) {
        dataStore.updateData { state }
        Log.d(TAG, "Saved LifeState: active=${state.activeTasks.size} logs=${state.actionLogs.size}")
    }

    companion object {
        fun create(context: Context): DataStoreLifeStateRepository =
            DataStoreLifeStateRepository(context.lifeStateDataStore)
    }
}

private val Context.lifeStateDataStore: DataStore<LifeState> by dataStore(
    fileName = DATA_STORE_FILE,
    serializer = LifeStateSerializer,
)

/**
 * kotlinx.serialization JSON codec for the DataStore file.
 */
object LifeStateSerializer : Serializer<LifeState> {
    override val defaultValue: LifeState = LifeState.EMPTY

    override suspend fun readFrom(input: InputStream): LifeState {
        return try {
            val bytes = input.readBytes()
            if (bytes.isEmpty()) return LifeState.EMPTY
            LookAfterJson.codec.decodeFromString(LifeState.serializer(), bytes.decodeToString())
        } catch (e: SerializationException) {
            throw CorruptionException("Cannot read LifeState JSON", e)
        } catch (e: IllegalArgumentException) {
            throw CorruptionException("Cannot read LifeState JSON", e)
        }
    }

    override suspend fun writeTo(t: LifeState, output: OutputStream) {
        val json = LookAfterJson.codec.encodeToString(LifeState.serializer(), t)
        output.write(json.encodeToByteArray())
    }
}
