package com.lookafter.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.lookafter.app.health.HealthConnectPermissionHelper
import com.lookafter.app.ui.LookAfterRootView
import com.lookafter.app.ui.theme.LookAfterTheme

/**
 * Compose entry point. Hosts [LookAfterViewModel], requests notification /
 * calendar / Health Connect permissions, and starts ExecutionService.
 */
class MainActivity : ComponentActivity() {

    private val viewModel: LookAfterViewModel by viewModels()

    private val notificationPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            Log.i(TAG, "POST_NOTIFICATIONS granted=$granted")
            (application as LookAfterApplication).startExecutionService()
        }

    private val calendarPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            Log.i(TAG, "READ_CALENDAR granted=$granted")
            if (granted) viewModel.refreshCalendarDay()
        }

    private lateinit var healthPermissionHelper: HealthConnectPermissionHelper

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        healthPermissionHelper = HealthConnectPermissionHelper(this) { granted ->
            Log.i(TAG, "Health Connect permissions granted=$granted")
            viewModel.onHealthPermissionResult(granted)
        }
        viewModel.requestHealthPermissions = { perms ->
            healthPermissionHelper.launch(perms)
        }
        viewModel.requestCalendarPermission = {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALENDAR)
                != PackageManager.PERMISSION_GRANTED
            ) {
                calendarPermissionLauncher.launch(Manifest.permission.READ_CALENDAR)
            } else {
                viewModel.refreshCalendarDay()
            }
        }

        requestNotificationPermissionAndStartService()

        setContent {
            LookAfterTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    val app = application as LookAfterApplication
                    val hydrationComplete by app.hydrationComplete.collectAsStateWithLifecycle()
                    val restoredFromDisk by app.restoredFromDisk.collectAsStateWithLifecycle()

                    LaunchedEffect(hydrationComplete, restoredFromDisk) {
                        if (!hydrationComplete) return@LaunchedEffect
                        val message = if (restoredFromDisk) {
                            "LifeState restored from disk"
                        } else {
                            "Fresh LifeState seeded (first launch)"
                        }
                        Log.i(TAG, message)
                        Toast.makeText(this@MainActivity, message, Toast.LENGTH_SHORT).show()
                        app.startExecutionService()
                        viewModel.refreshCalendarDay()
                    }

                    LookAfterRootView(
                        viewModel = viewModel,
                        restoredFromDisk = restoredFromDisk,
                        hydrationComplete = hydrationComplete,
                    )
                }
            }
        }
    }

    private fun requestNotificationPermissionAndStartService() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            (application as LookAfterApplication).startExecutionService()
            return
        }
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) {
            (application as LookAfterApplication).startExecutionService()
        } else {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    companion object {
        private const val TAG = "MainActivity"
    }
}
