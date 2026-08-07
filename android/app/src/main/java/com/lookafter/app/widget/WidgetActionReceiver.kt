package com.lookafter.app.widget

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import android.widget.Toast
import com.lookafter.app.LookAfterApplication
import com.lookafter.core.brain.ExecutiveBrainEngine
import com.lookafter.core.engine.LookAfterIntent
import com.lookafter.core.health.HealthSummary
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Handles home-screen widget actions that do not require the Compose UI
 * (e.g. complete hero task). Re-enters [LifeEngine] on the application process.
 */
class WidgetActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        val app = context.applicationContext as? LookAfterApplication ?: return
        val pending = goAsync()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        scope.launch {
            try {
                when (action) {
                    ACTION_COMPLETE_HERO -> completeHero(app, context)
                    else -> Log.d(TAG, "Unknown action $action")
                }
            } finally {
                pending.finish()
            }
        }
    }

    private suspend fun completeHero(app: LookAfterApplication, context: Context) {
        val life = app.lifeEngine.currentState
        val health = app.healthRepository.summary.value
        val tick = ExecutiveBrainEngine.tick(life, health)
        val heroId = tick.decision.heroTaskId
        if (heroId.isNullOrBlank()) {
            Log.i(TAG, "No hero to complete")
            showToast(context, "Nothing open to complete")
            return
        }
        app.lifeEngine.process(
            LookAfterIntent.CompleteTask(id = heroId, completedAt = Instant.now()),
        )
        TodayWidgetUpdater.requestUpdate(context)
        val title = tick.decision.heroTitle
        showToast(context, "Completed: $title")
        Log.i(TAG, "Completed hero $heroId")
    }

    private fun showToast(context: Context, message: String) {
        CoroutineScope(Dispatchers.Main).launch {
            Toast.makeText(context.applicationContext, message, Toast.LENGTH_SHORT).show()
        }
    }

    companion object {
        private const val TAG = "WidgetAction"
        const val ACTION_COMPLETE_HERO = "com.lookafter.app.widget.COMPLETE_HERO"
    }
}
