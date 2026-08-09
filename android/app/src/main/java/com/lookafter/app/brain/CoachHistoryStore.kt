package com.lookafter.app.brain

import android.content.Context
import com.lookafter.core.brain.CoachHistoryState
import com.lookafter.core.serialization.LookAfterJson

/** Persists pinned coach decisions & history across process death. */
class CoachHistoryStore(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun load(): CoachHistoryState {
        val raw = prefs.getString(KEY, null) ?: return CoachHistoryState.EMPTY
        return runCatching {
            LookAfterJson.codec.decodeFromString(CoachHistoryState.serializer(), raw)
        }.getOrDefault(CoachHistoryState.EMPTY)
    }

    fun save(state: CoachHistoryState) {
        prefs.edit()
            .putString(
                KEY,
                LookAfterJson.codec.encodeToString(CoachHistoryState.serializer(), state),
            )
            .apply()
    }

    fun clear() {
        prefs.edit().remove(KEY).apply()
    }

    companion object {
        private const val PREFS = "lookafter_coach_history"
        private const val KEY = "state_json"
    }
}
