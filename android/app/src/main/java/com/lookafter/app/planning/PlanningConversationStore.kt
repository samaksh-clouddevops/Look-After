package com.lookafter.app.planning

import android.content.Context
import com.lookafter.core.planning.PlanningConversationEngine
import com.lookafter.core.planning.PlanningConversationState
import com.lookafter.core.serialization.LookAfterJson

/**
 * Persists the Brain planning conversation (messages, pending plan, horizon)
 * so it survives process death.
 */
class PlanningConversationStore(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun load(): PlanningConversationState {
        val raw = prefs.getString(KEY, null) ?: return PlanningConversationState()
        return runCatching {
            LookAfterJson.codec.decodeFromString(PlanningConversationState.serializer(), raw)
        }.getOrDefault(PlanningConversationState())
    }

    fun save(state: PlanningConversationState) {
        val compact = PlanningConversationEngine.compactForStorage(state)
        prefs.edit()
            .putString(
                KEY,
                LookAfterJson.codec.encodeToString(PlanningConversationState.serializer(), compact),
            )
            .apply()
    }

    fun clear() {
        prefs.edit().remove(KEY).apply()
    }

    companion object {
        private const val PREFS = "lookafter_planning_conversation"
        private const val KEY = "state_json"
    }
}
