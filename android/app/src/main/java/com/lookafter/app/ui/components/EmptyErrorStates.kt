package com.lookafter.app.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material.icons.outlined.SelfImprovement
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.lookafter.app.ui.motion.CalmEntrance
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens

@Composable
fun CalmEmptyState(
    title: String,
    subtitle: String,
    icon: ImageVector = Icons.Outlined.SelfImprovement,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    CalmEntrance(modifier = modifier.fillMaxWidth()) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = LookAfterDimens.spacingXL),
        ) {
            Icon(
                icon,
                contentDescription = null,
                tint = LookAfterColors.AccentPrimary,
                modifier = Modifier.size(40.dp),
            )
            Text(title, style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)
            Text(
                subtitle,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
            if (actionLabel != null && onAction != null) {
                Button(
                    onClick = onAction,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = LookAfterColors.AccentPrimary,
                        contentColor = LookAfterColors.AccentOnPrimary,
                    ),
                ) { Text(actionLabel) }
            }
        }
    }
}

@Composable
fun CalmErrorState(
    title: String = "Something went quiet",
    message: String,
    onRetry: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    CalmEntrance(modifier = modifier.fillMaxWidth()) {
        ElevatedSurfaceCard {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(
                    Icons.Outlined.ErrorOutline,
                    contentDescription = null,
                    tint = LookAfterColors.Warning,
                    modifier = Modifier.size(36.dp),
                )
                Text(title, style = MaterialTheme.typography.titleLarge)
                Text(
                    message,
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
                if (onRetry != null) {
                    TextButton(onClick = onRetry) { Text("Try again") }
                }
            }
        }
    }
}

@Composable
fun OfflineBanner(
    onDismiss: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    ElevatedSurfaceCard(modifier = modifier) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            RowIconText(
                icon = Icons.Outlined.CloudOff,
                title = "Working offline",
                subtitle = "Cloud coach unavailable — local brain is active.",
            )
            if (onDismiss != null) {
                TextButton(onClick = onDismiss) { Text("Dismiss") }
            }
        }
    }
}

@Composable
private fun RowIconText(icon: ImageVector, title: String, subtitle: String) {
    Column {
        Icon(icon, contentDescription = null, tint = LookAfterColors.AccentPrimary)
        Text(title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 6.dp))
        Text(
            subtitle,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

val EmptyInboxIcon = Icons.Outlined.Inbox
