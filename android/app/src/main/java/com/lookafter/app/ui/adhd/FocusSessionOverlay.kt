package com.lookafter.app.ui.adhd

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.core.adhd.FocusSessionIntent
import com.lookafter.core.adhd.FocusSessionPhase
import com.lookafter.core.adhd.FocusSessionState
import java.time.Instant
import kotlinx.coroutines.delay

/** Full-screen ADHD focus lock - body-doubling prompts + timer (iOS parity). */
@Composable
fun FocusSessionOverlay(
    session: FocusSessionState,
    onIntent: (FocusSessionIntent) -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var remaining by remember(session.phase, session.startedAt, session.accumulatedActiveSeconds) {
        mutableLongStateOf(session.remainingSeconds())
    }
    var elapsed by remember(session.phase, session.startedAt, session.accumulatedActiveSeconds) {
        mutableLongStateOf(session.elapsedActiveSeconds())
    }

    LaunchedEffect(session.phase, session.startedAt, session.emergencyMode) {
        while (session.phase == FocusSessionPhase.RUNNING) {
            val now = Instant.now()
            remaining = session.remainingSeconds(now)
            elapsed = session.elapsedActiveSeconds(now)
            onIntent(FocusSessionIntent.Tick(now))
            if (remaining <= 0) break
            delay(1000)
        }
        remaining = session.remainingSeconds()
        elapsed = session.elapsedActiveSeconds()
    }

    val mins = remaining / 60
    val secs = remaining % 60
    val accent = if (session.emergencyMode) LookAfterColors.Warning else LookAfterColors.AccentPrimary
    val emergency = session.emergencyMode
    val onBg = if (emergency) LookAfterColors.DarkTextPrimary else MaterialTheme.colorScheme.onBackground
    val muted = if (emergency) LookAfterColors.DarkTextSecondary else MaterialTheme.colorScheme.onSurfaceVariant

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(if (emergency) LookAfterColors.DarkBackground else MaterialTheme.colorScheme.background)
            .padding(LookAfterDimens.screenHorizontal)
            .padding(vertical = LookAfterDimens.spacingXL),
        verticalArrangement = Arrangement.SpaceBetween,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = if (emergency) "Emergency focus" else "Focus",
                style = MaterialTheme.typography.labelMedium,
                color = accent,
            )
            Text(
                text = session.taskTitle.ifBlank { "Deep work" },
                style = MaterialTheme.typography.headlineMedium,
                color = onBg,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = LookAfterDimens.spacingSM),
            )
            Text(
                text = "%d:%02d".format(mins, secs),
                style = MaterialTheme.typography.displayLarge,
                color = onBg,
                modifier = Modifier.padding(top = LookAfterDimens.spacingLG),
            )
            LinearProgressIndicator(
                progress = { session.progress },
                modifier = Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingMD),
                color = accent,
            )
            Text(
                text = session.phase.name.lowercase(),
                style = MaterialTheme.typography.bodyLarge,
                color = muted,
                modifier = Modifier.padding(top = 8.dp),
            )
            BodyDoublePresencePanel(
                emergency = emergency,
                elapsedActiveSeconds = elapsed,
                modifier = Modifier.padding(top = LookAfterDimens.spacingLG),
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
            ) {
                when (session.phase) {
                    FocusSessionPhase.RUNNING -> {
                        Button(
                            onClick = { onIntent(FocusSessionIntent.Pause()) },
                            modifier = Modifier.weight(1f),
                            colors = ButtonDefaults.buttonColors(containerColor = accent),
                        ) { Text("Pause") }
                    }
                    FocusSessionPhase.PAUSED -> {
                        Button(
                            onClick = { onIntent(FocusSessionIntent.Resume()) },
                            modifier = Modifier.weight(1f),
                            colors = ButtonDefaults.buttonColors(containerColor = accent),
                        ) { Text("Resume") }
                    }
                    else -> Unit
                }
                Button(
                    onClick = {
                        onIntent(FocusSessionIntent.Complete())
                        onClose()
                    },
                    modifier = Modifier.weight(1f),
                ) { Text("Complete") }
            }
            TextButton(
                onClick = {
                    onIntent(FocusSessionIntent.Abort())
                    onClose()
                },
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Abort session") }
        }
    }
}
