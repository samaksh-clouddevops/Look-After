package com.lookafter.app.ui

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.lookafter.app.LookAfterViewModel
import com.lookafter.app.ui.navigation.AppDestination
import com.lookafter.app.ui.review.WeeklyReviewScreen
import com.lookafter.app.ui.timeline.TodayTimelineScreen

/**
 * App root — bottom nav between Today timeline and Weekly Review.
 * Collects LifeState and forwards intents to the ViewModel.
 */
@Composable
fun LookAfterRootView(
    viewModel: LookAfterViewModel,
    restoredFromDisk: Boolean = false,
    hydrationComplete: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var destination by rememberSaveable { mutableStateOf(AppDestination.TODAY.name) }
    val current = AppDestination.entries.firstOrNull { it.name == destination }
        ?: AppDestination.TODAY

    Scaffold(
        modifier = modifier.fillMaxSize(),
        bottomBar = {
            NavigationBar {
                AppDestination.entries.forEach { dest ->
                    NavigationBarItem(
                        selected = dest == current,
                        onClick = { destination = dest.name },
                        icon = {
                            Icon(
                                imageVector = dest.icon,
                                contentDescription = dest.label,
                            )
                        },
                        label = { Text(dest.label) },
                    )
                }
            }
        },
    ) { padding ->
        val contentModifier = Modifier
            .padding(padding)
            .fillMaxSize()

        when (current) {
            AppDestination.TODAY -> TodayTimelineScreen(
                state = state,
                onIntent = viewModel::dispatch,
                restoredFromDisk = restoredFromDisk,
                hydrationComplete = hydrationComplete,
                modifier = contentModifier,
            )
            AppDestination.REVIEW -> WeeklyReviewScreen(
                state = state,
                modifier = contentModifier,
            )
        }
    }
}
