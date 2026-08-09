package com.lookafter.app.travel

import android.content.Context
import com.lookafter.core.serialization.LookAfterJson
import com.lookafter.core.travel.TravelState

/** Persists [TravelState] in SharedPreferences. */
class TravelStore(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun load(): TravelState {
        val raw = prefs.getString(KEY, null) ?: return TravelState.EMPTY
        return runCatching {
            LookAfterJson.codec.decodeFromString(TravelState.serializer(), raw)
        }.getOrDefault(TravelState.EMPTY)
    }

    fun save(state: TravelState) {
        prefs.edit()
            .putString(
                KEY,
                LookAfterJson.codec.encodeToString(TravelState.serializer(), state),
            )
            .apply()
    }

    fun clear() {
        prefs.edit().remove(KEY).apply()
    }

    companion object {
        private const val PREFS = "lookafter_travel"
        private const val KEY = "state_json"
    }
}
