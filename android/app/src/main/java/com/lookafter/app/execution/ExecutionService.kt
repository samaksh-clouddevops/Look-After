package com.lookafter.app.execution

import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.ServiceCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import com.lookafter.app.LookAfterApplication
import com.lookafter.core.engine.LifeEngine
import com.lookafter.core.execution.ExecutionBlockResolver
import com.lookafter.core.models.ExecutionBlockSnapshot
import java.time.Instant
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Android counterpart to iOS Live Activities.
 *
 * Observes [LifeEngine.state], resolves the active focus block via
 * [ExecutionBlockResolver], and projects it as an ongoing foreground notification.
 * Self-stops when the universe has no focus-eligible block.
 */
class ExecutionService : LifecycleService() {

    private lateinit var engine: LifeEngine
    private lateinit var notifications: ExecutionNotificationHelper
    private var observeJob: Job? = null
    private var isForeground: Boolean = false
    private var lastTaskId: String? = null

    override fun onCreate() {
        super.onCreate()
        val app = application as LookAfterApplication
        engine = app.lifeEngine
        notifications = ExecutionNotificationHelper(this)
        notifications.ensureChannel()
        Log.i(TAG, "ExecutionService created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        // Android requires startForeground within ~5s of startForegroundService.
        if (!isForeground) {
            startAsForeground(notifications.buildBootstrap())
            isForeground = true
        }
        if (observeJob == null) {
            observeJob = lifecycleScope.launch {
                // Immediate resolve against current universe.
                publish(ExecutionBlockResolver.resolve(engine.state.value, Instant.now()))
                // Tick so progress / chronometer stay fresh during quiet state.
                launch {
                    while (isActive) {
                        delay(TICK_MS)
                        publish(ExecutionBlockResolver.resolve(engine.state.value, Instant.now()))
                    }
                }
                engine.state
                    .map { ExecutionBlockResolver.resolve(it, Instant.now()) }
                    .distinctUntilChanged { a, b ->
                        a.taskId == b.taskId &&
                            a.surfaceMode == b.surfaceMode &&
                            a.windowEnd == b.windowEnd &&
                            a.isFocusEligible == b.isFocusEligible
                    }
                    .collectLatest { publish(it) }
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent): IBinder? {
        super.onBind(intent)
        return null
    }

    override fun onDestroy() {
        observeJob?.cancel()
        observeJob = null
        super.onDestroy()
        Log.i(TAG, "ExecutionService destroyed")
    }

    private fun publish(snapshot: ExecutionBlockSnapshot) {
        if (!snapshot.isFocusEligible) {
            if (isForeground) {
                ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
                isForeground = false
                lastTaskId = null
                Log.i(TAG, "No focus block — stopping foreground")
            }
            stopSelf()
            return
        }

        val notification = notifications.build(snapshot)
        if (!isForeground) {
            startAsForeground(notification)
            isForeground = true
            lastTaskId = snapshot.taskId
            Log.i(TAG, "Foreground for task=${snapshot.taskId} '${snapshot.taskTitle}'")
        } else {
            notifications.notify(snapshot)
            if (lastTaskId != snapshot.taskId) {
                lastTaskId = snapshot.taskId
                Log.i(TAG, "Updated focus task=${snapshot.taskId}")
            }
        }
    }

    private fun startAsForeground(notification: android.app.Notification) {
        if (Build.VERSION.SDK_INT >= 34) {
            ServiceCompat.startForeground(
                this,
                ExecutionNotificationHelper.NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            @Suppress("DEPRECATION")
            startForeground(ExecutionNotificationHelper.NOTIFICATION_ID, notification)
        }
    }

    companion object {
        private const val TAG = "ExecutionService"
        private const val TICK_MS = 30_000L

        fun start(context: Context) {
            val intent = Intent(context, ExecutionService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }
}
