package com.lookafter.app.learning

import android.content.Context
import com.lookafter.core.learning.LearningEngine
import com.lookafter.core.learning.LearningState
import com.lookafter.core.serialization.LookAfterJson
import java.time.Instant

/** Persists learning tracks & cards; seeds a default track when empty. */
class LearningStore(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun load(): LearningState {
        val raw = prefs.getString(KEY, null) ?: return seed()
        return runCatching {
            LookAfterJson.codec.decodeFromString(LearningState.serializer(), raw)
        }.getOrElse { seed() }
    }

    fun save(state: LearningState) {
        prefs.edit()
            .putString(
                KEY,
                LookAfterJson.codec.encodeToString(LearningState.serializer(), state),
            )
            .apply()
    }

    fun clear() {
        prefs.edit().remove(KEY).apply()
    }

    private fun seed(): LearningState {
        val track = LearningEngine.defaultTrack(Instant.now())
        return LearningState(tracks = listOf(track), selectedTrackId = track.id)
    }

    companion object {
        private const val PREFS = "lookafter_learning"
        private const val KEY = "state_json"
    }
}
