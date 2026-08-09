package com.lookafter.app.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.lookafter.app.ui.components.ElevatedSurfaceCard
import com.lookafter.app.ui.components.SectionHeader
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.core.notifications.NotificationPreferences
import kotlin.math.roundToInt

@Composable
fun NotificationSettingsScreen(
    prefs: NotificationPreferences,
    onChange: (NotificationPreferences) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            horizontal = LookAfterDimens.screenHorizontal,
            vertical = LookAfterDimens.spacingLG,
        ),
        verticalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingMD),
    ) {
        item {
            SectionHeader(
                title = "Notifications",
                subtitle = "What pings — and when quiet wins",
            )
        }
        item {
            PrefSwitch(
                title = "Medication due",
                subtitle = "When a dose enters the due window",
                checked = prefs.medicationsEnabled,
                onChecked = { onChange(prefs.copy(medicationsEnabled = it)) },
            )
        }
        item {
            PrefSwitch(
                title = "Anchored lead-in",
                subtitle = "Reminder before fixed blocks",
                checked = prefs.anchoredEnabled,
                onChecked = { onChange(prefs.copy(anchoredEnabled = it)) },
            )
        }
        if (prefs.anchoredEnabled) {
            item {
                ElevatedSurfaceCard {
                    Text("Lead time", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "${prefs.anchoredLeadMinutes} minutes before start",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Slider(
                        value = prefs.anchoredLeadMinutes.toFloat(),
                        onValueChange = {
                            onChange(prefs.copy(anchoredLeadMinutes = it.roundToInt().coerceIn(5, 60)))
                        },
                        valueRange = 5f..60f,
                        steps = 10,
                        colors = SliderDefaults.colors(thumbColor = LookAfterColors.AccentPrimary),
                        modifier = Modifier.padding(top = LookAfterDimens.spacingSM),
                    )
                }
            }
        }
        item {
            PrefSwitch(
                title = "Daily briefing nudge",
                subtitle = "Soft open when the board is full and unfinished",
                checked = prefs.briefingEnabled,
                onChecked = { onChange(prefs.copy(briefingEnabled = it)) },
            )
        }
        item {
            PrefSwitch(
                title = "Focus complete",
                subtitle = "Notify when a timed focus block ends",
                checked = prefs.focusCompleteEnabled,
                onChecked = { onChange(prefs.copy(focusCompleteEnabled = it)) },
            )
        }
        item {
            PrefSwitch(
                title = "Suppress during focus",
                subtitle = "Hold pings while a focus session is running",
                checked = prefs.suppressDuringFocus,
                onChecked = { onChange(prefs.copy(suppressDuringFocus = it)) },
            )
        }
        item {
            PrefSwitch(
                title = "Quiet hours",
                subtitle = prefs.quietWindowLabel(),
                checked = prefs.quietHoursEnabled,
                onChecked = { onChange(prefs.copy(quietHoursEnabled = it)) },
            )
        }
        if (prefs.quietHoursEnabled) {
            item {
                QuietHoursSliders(prefs = prefs, onChange = onChange)
            }
        }
        item {
            PrefSwitch(
                title = "Haptics on Today",
                subtitle = "Soft tick when you complete or park",
                checked = prefs.hapticsEnabled,
                onChecked = { onChange(prefs.copy(hapticsEnabled = it)) },
            )
        }
        item {
            Text(
                "Back",
                color = LookAfterColors.AccentPrimary,
                modifier = Modifier
                    .clickable(onClick = onBack)
                    .padding(top = LookAfterDimens.spacingSM),
            )
        }
    }
}

@Composable
private fun PrefSwitch(
    title: String,
    subtitle: String,
    checked: Boolean,
    onChecked: (Boolean) -> Unit,
) {
    ElevatedSurfaceCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.titleLarge)
                Text(
                    subtitle,
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Switch(
                checked = checked,
                onCheckedChange = onChecked,
                colors = SwitchDefaults.colors(checkedTrackColor = LookAfterColors.AccentPrimary),
            )
        }
    }
}

@Composable
private fun QuietHoursSliders(
    prefs: NotificationPreferences,
    onChange: (NotificationPreferences) -> Unit,
) {
    ElevatedSurfaceCard {
        Text("Quiet window", style = MaterialTheme.typography.titleMedium)
        Text(
            "Start ${"%02d".format(prefs.quietHoursStartHour)}:00",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = LookAfterDimens.spacingSM),
        )
        Slider(
            value = prefs.quietHoursStartHour.toFloat(),
            onValueChange = {
                onChange(prefs.copy(quietHoursStartHour = it.roundToInt().coerceIn(0, 23)))
            },
            valueRange = 0f..23f,
            steps = 22,
            colors = SliderDefaults.colors(thumbColor = LookAfterColors.AccentPrimary),
        )
        Text(
            "End ${"%02d".format(prefs.quietHoursEndHour)}:00",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Slider(
            value = prefs.quietHoursEndHour.toFloat(),
            onValueChange = {
                onChange(prefs.copy(quietHoursEndHour = it.roundToInt().coerceIn(0, 23)))
            },
            valueRange = 0f..23f,
            steps = 22,
            colors = SliderDefaults.colors(thumbColor = LookAfterColors.AccentPrimary),
        )
    }
}
