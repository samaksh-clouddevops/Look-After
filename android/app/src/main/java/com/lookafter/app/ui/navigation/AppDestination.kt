package com.lookafter.app.ui.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Article
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Psychology
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * Bottom-nav destinations — mirrors iOS `LookAfterTab`
 * (Briefing / Today / Brain / You + center Capture).
 */
enum class AppDestination(
    val label: String,
    val icon: ImageVector,
    val selectedIcon: ImageVector = icon,
) {
    BRIEFING(
        label = "Briefing",
        icon = Icons.AutoMirrored.Outlined.Article,
    ),
    TODAY(
        label = "Today",
        icon = Icons.Outlined.CalendarMonth,
    ),
    BRAIN(
        label = "Brain",
        icon = Icons.Outlined.Psychology,
    ),
    YOU(
        label = "You",
        icon = Icons.Outlined.Person,
        selectedIcon = Icons.Filled.Person,
    ),
}
