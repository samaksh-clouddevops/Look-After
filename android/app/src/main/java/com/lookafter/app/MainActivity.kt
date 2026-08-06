package com.lookafter.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import com.lookafter.app.ui.LookAfterRootView

/**
 * Compose entry point. Hosts [LookAfterViewModel] and the Phase-3 proof UI.
 */
class MainActivity : ComponentActivity() {

    private val viewModel: LookAfterViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MaterialTheme {
                Surface {
                    LookAfterRootView(viewModel = viewModel)
                }
            }
        }
    }
}
