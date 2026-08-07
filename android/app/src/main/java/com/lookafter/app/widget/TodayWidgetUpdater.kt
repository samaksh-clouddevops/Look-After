package com.lookafter.app.widget

import android.content.Context
import android.util.Log
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.updateAll
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Fire-and-forget Glance refresh when LifeState / health changes.
 * Safe no-op when no widget instances are pinned.
 */
object TodayWidgetUpdater {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private const val TAG = "TodayWidget"

    fun requestUpdate(context: Context) {
        val appContext = context.applicationContext
        scope.launch {
            runCatching {
                // Ensure manager is warm, then update every instance.
                GlanceAppWidgetManager(appContext)
                TodayGlanceWidget().updateAll(appContext)
                Log.d(TAG, "Glance widgets refreshed")
            }.onFailure {
                Log.d(TAG, "Widget refresh skipped: ${it.message}")
            }
        }
    }
}
