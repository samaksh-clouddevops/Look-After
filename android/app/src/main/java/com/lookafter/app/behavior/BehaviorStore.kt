package com.lookafter.app.behavior

import android.content.Context
import com.lookafter.core.behavior.BehaviorState
import com.lookafter.core.serialization.LookAfterJson

/** Local persistence for habits (Phase E5). */
class BehaviorStore(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun load(): BehaviorState {
        val raw = prefs.getString(KEY, null) ?: return BehaviorState.EMPTY
        return runCatching {
            LookAfterJson.codec.decodeFromString(BehaviorState.serializer(), raw)
        }.getOrDefault(BehaviorState.EMPTY)
    }

    fun save(state: BehaviorState) {
        prefs.edit()
            .putString(
                KEY,
                LookAfterJson.codec.encodeToString(BehaviorState.serializer(), state),
            )
            .apply()
    }

    fun clear() {
        prefs.edit().remove(KEY).apply()
    }

    companion object {
        private const val PREFS = "lookafter_behavior"
        private const val KEY = "state_json"
    }
}
