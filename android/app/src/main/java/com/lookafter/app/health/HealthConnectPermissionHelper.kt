package com.lookafter.app.health

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContract
import androidx.health.connect.client.PermissionController

/**
 * Registers the Health Connect permission contract on a [ComponentActivity].
 * Falls back to a no-op launcher when the SDK contract cannot be created.
 */
class HealthConnectPermissionHelper(
    activity: ComponentActivity,
    private val onResult: (granted: Boolean) -> Unit,
) {
    private val requestPermission: ActivityResultLauncher<Set<String>> =
        runCatching {
            activity.registerForActivityResult(
                PermissionController.createRequestPermissionResultContract(),
            ) { granted: Set<String> ->
                onResult(granted.isNotEmpty())
            }
        }.getOrElse {
            // Fallback contract so Activity can still call launch safely in tests/demo.
            activity.registerForActivityResult(object : ActivityResultContract<Set<String>, Set<String>>() {
                override fun createIntent(context: Context, input: Set<String>): Intent =
                    Intent(Intent.ACTION_VIEW).apply {
                        data = Uri.parse("market://details?id=com.google.android.apps.healthdata")
                    }
                override fun parseResult(resultCode: Int, intent: Intent?): Set<String> = emptySet()
            }) { onResult(false) }
        }

    fun launch(permissions: Set<String>) {
        if (permissions.isEmpty()) {
            onResult(true)
            return
        }
        runCatching { requestPermission.launch(permissions) }
            .onFailure { onResult(false) }
    }

    companion object {
        fun openHealthConnectInstall(context: Context) {
            val intent = Intent(Intent.ACTION_VIEW).apply {
                data = Uri.parse("market://details?id=com.google.android.apps.healthdata")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            runCatching { context.startActivity(intent) }
        }
    }
}
