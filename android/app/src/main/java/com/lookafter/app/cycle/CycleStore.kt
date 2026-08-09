package com.lookafter.app.cycle

import android.content.Context
import com.lookafter.core.cycle.CycleState
import com.lookafter.core.serialization.LookAfterJson

/** Persists [CycleState] locally (privacy-first; never syncs by default). */
class CycleStore(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun load(): CycleState {
        val raw = prefs.getString(KEY, null) ?: return CycleState.EMPTY
        return runCatching {
            LookAfterJson.codec.decodeFromString(CycleState.serializer(), raw)
        }.getOrDefault(CycleState.EMPTY)
    }

    fun save(state: CycleState) {
        prefs.edit()
            .putString(
                KEY,
                LookAfterJson.codec.encodeToString(CycleState.serializer(), state),
            )
            .apply()
    }

    fun clear() {
        prefs.edit().remove(KEY).apply()
    }

    companion object {
        private const val PREFS = "lookafter_cycle"
        private const val KEY = "state_json"
    }
}
