package com.lookafter.app.notifications

import android.content.Context
import com.lookafter.core.notifications.NotificationKind
import com.lookafter.core.notifications.PlannedNotification
import com.lookafter.core.serialization.LookAfterJson
import java.time.Instant
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer

/**
 * Persists the last notification plan so [BootNotificationReceiver] can
 * re-arm alarms after reboot without needing a full UI session.
 */
class NotificationPlanStore(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun save(plans: List<PlannedNotification>) {
        val payload = plans.map {
            StoredPlan(
                id = it.id,
                kind = it.kind.name,
                title = it.title,
                body = it.body,
                fireAtEpochMs = it.fireAt.toEpochMilli(),
            )
        }
        val json = LookAfterJson.codec.encodeToString(
            ListSerializer(StoredPlan.serializer()),
            payload,
        )
        prefs.edit().putString(KEY_PLANS, json).apply()
    }

    fun load(): List<PlannedNotification> {
        val raw = prefs.getString(KEY_PLANS, null) ?: return emptyList()
        return runCatching {
            LookAfterJson.codec.decodeFromString(
                ListSerializer(StoredPlan.serializer()),
                raw,
            ).mapNotNull { stored ->
                val kind = runCatching { NotificationKind.valueOf(stored.kind) }
                    .getOrNull() ?: return@mapNotNull null
                PlannedNotification(
                    id = stored.id,
                    kind = kind,
                    title = stored.title,
                    body = stored.body,
                    fireAt = Instant.ofEpochMilli(stored.fireAtEpochMs),
                )
            }
        }.getOrDefault(emptyList())
    }

    fun clear() {
        prefs.edit().remove(KEY_PLANS).apply()
    }

    @Serializable
    private data class StoredPlan(
        val id: String,
        val kind: String,
        val title: String,
        val body: String,
        val fireAtEpochMs: Long,
    )

    companion object {
        private const val PREFS = "lookafter_notification_plans"
        private const val KEY_PLANS = "plans_json"
    }
}
