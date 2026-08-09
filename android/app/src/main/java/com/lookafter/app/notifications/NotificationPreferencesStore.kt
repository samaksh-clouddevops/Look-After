package com.lookafter.app.notifications

import android.content.Context
import com.lookafter.core.notifications.NotificationPreferences
import com.lookafter.core.serialization.LookAfterJson
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Persists [NotificationPreferences] in SharedPreferences. */
class NotificationPreferencesStore(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private val _state = MutableStateFlow(load())
    val state: StateFlow<NotificationPreferences> = _state.asStateFlow()

    fun update(transform: (NotificationPreferences) -> NotificationPreferences) {
        persist(transform(_state.value))
    }

    fun set(next: NotificationPreferences) {
        persist(next)
    }

    private fun load(): NotificationPreferences {
        val raw = prefs.getString(KEY, null) ?: return NotificationPreferences.DEFAULT
        return runCatching {
            LookAfterJson.codec.decodeFromString(NotificationPreferences.serializer(), raw)
        }.getOrDefault(NotificationPreferences.DEFAULT)
    }

    private fun persist(next: NotificationPreferences) {
        _state.value = next
        prefs.edit()
            .putString(
                KEY,
                LookAfterJson.codec.encodeToString(NotificationPreferences.serializer(), next),
            )
            .apply()
    }

    companion object {
        private const val PREFS = "lookafter_notification_prefs"
        private const val KEY = "prefs_json"
    }
}
