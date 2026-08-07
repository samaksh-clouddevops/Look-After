package com.lookafter.app.ui.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CalendarViewDay
import androidx.compose.material.icons.outlined.Insights
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * Bottom-nav destinations for the Phase-6 shell.
 */
enum class AppDestination(
    val label: String,
    val icon: ImageVector,
) {
    TODAY(label = "Today", icon = Icons.Outlined.CalendarViewDay),
    REVIEW(label = "Review", icon = Icons.Outlined.Insights),
}
