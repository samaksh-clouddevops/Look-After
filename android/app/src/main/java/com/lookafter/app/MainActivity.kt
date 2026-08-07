package com.lookafter.app

import android.os.Bundle
import android.util.Log
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.lookafter.app.ui.LookAfterRootView

/**
 * Compose entry point. Hosts [LookAfterViewModel] and the Phase-3/4 proof UI.
 */
class MainActivity : ComponentActivity() {

    private val viewModel: LookAfterViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MaterialTheme {
                Surface {
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

    companion object {
        private const val TAG = "MainActivity"
    }
}
