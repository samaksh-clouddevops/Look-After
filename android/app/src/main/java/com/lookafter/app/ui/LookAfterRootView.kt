package com.lookafter.app.ui

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.lookafter.app.LookAfterViewModel
import com.lookafter.app.ui.timeline.TodayTimelineScreen

/**
 * App root content. Theme is applied above this in [com.lookafter.app.MainActivity].
 * Collects [com.lookafter.core.engine.LifeState] and forwards intents to the ViewModel.
 */
@Composable
fun LookAfterRootView(
    viewModel: LookAfterViewModel,
    restoredFromDisk: Boolean = false,
    hydrationComplete: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()

    Scaffold(modifier = modifier.fillMaxSize()) { padding ->
        TodayTimelineScreen(
            state = state,
            onIntent = viewModel::dispatch,
            restoredFromDisk = restoredFromDisk,
            hydrationComplete = hydrationComplete,
            modifier = Modifier
                .padding(padding)
                .fillMaxSize(),
        )
    }
}
