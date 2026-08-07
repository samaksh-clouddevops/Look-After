package com.lookafter.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lookafter.app.ui.navigation.AppDestination
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens

/** iOS-parity bottom nav: Briefing | Today | [Capture +] | Brain | You */
@Composable
fun LookAfterBottomNav(
    current: AppDestination,
    onSelect: (AppDestination) -> Unit,
    onCapture: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surface,
        tonalElevation = 0.dp,
        shadowElevation = 0.dp,
    ) {
        Column {
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant, thickness = 1.dp)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = LookAfterDimens.spacingSM)
                    .padding(top = 10.dp, bottom = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                NavTab(AppDestination.BRIEFING, current == AppDestination.BRIEFING, onSelect)
                NavTab(AppDestination.TODAY, current == AppDestination.TODAY, onSelect)
                CaptureButton(onClick = onCapture)
                NavTab(AppDestination.BRAIN, current == AppDestination.BRAIN, onSelect)
                NavTab(AppDestination.YOU, current == AppDestination.YOU, onSelect)
            }
        }
    }
}

@Composable
private fun RowScope.NavTab(
    dest: AppDestination,
    selected: Boolean,
    onSelect: (AppDestination) -> Unit,
) {
    val tint = if (selected) LookAfterColors.AccentPrimary else MaterialTheme.colorScheme.onSurfaceVariant
    val weight = if (selected) FontWeight.SemiBold else FontWeight.Medium
    val icon: ImageVector = if (selected) dest.selectedIcon else dest.icon

    Column(
        modifier = Modifier
            .weight(1f)
            .clickable { onSelect(dest) }
            .padding(vertical = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = dest.label,
            tint = tint,
            modifier = Modifier.size(22.dp),
        )
        Text(
            text = dest.label,
            style = MaterialTheme.typography.labelSmall.copy(fontWeight = weight),
            color = tint,
            maxLines = 1,
        )
    }
}

@Composable
private fun RowScope.CaptureButton(onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .weight(1f)
            .offset(y = (-8).dp),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .size(48.dp)
                .clip(CircleShape)
                .background(LookAfterColors.AccentPrimary)
                .clickable(onClick = onClick),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Filled.Add,
                contentDescription = "Capture",
                tint = LookAfterColors.AccentOnPrimary,
                modifier = Modifier.size(28.dp),
            )
        }
    }
}
