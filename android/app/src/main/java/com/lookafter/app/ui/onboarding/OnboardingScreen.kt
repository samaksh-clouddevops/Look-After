package com.lookafter.app.ui.onboarding

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.core.onboarding.OnboardingIntent
import com.lookafter.core.onboarding.OnboardingState
import com.lookafter.core.onboarding.OnboardingStep

@Composable
fun OnboardingScreen(
    state: OnboardingState,
    onIntent: (OnboardingIntent) -> Unit,
    modifier: Modifier = Modifier,
) {
    var name by remember(state.displayName) { mutableStateOf(state.displayName) }
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(LookAfterDimens.screenHorizontal)
            .padding(vertical = LookAfterDimens.spacingXL),
        verticalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingMD),
    ) {
        Text("Look After", style = MaterialTheme.typography.displayLarge)
        when (state.step) {
            OnboardingStep.WELCOME -> {
                Text("Calm execution for a noisy brain.", style = MaterialTheme.typography.titleLarge)
                Text(
                    "One source of truth for tasks, meds, focus, and health.",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                OutlinedTextField(
                    value = name,
                    onValueChange = {
                        name = it
                        onIntent(OnboardingIntent.SetName(it))
                    },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("What should we call you?") },
                    singleLine = true,
                )
            }
            OnboardingStep.CAPTURE_INTENT -> {
                Text("Capture is sacred", style = MaterialTheme.typography.headlineMedium)
                Text(
                    "The center + button parks thoughts as fluid work. Schedule later — never lose them.",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            OnboardingStep.HEALTH_PERMISSION -> {
                Text("Health readiness", style = MaterialTheme.typography.headlineMedium)
                Text(
                    "We'll read sleep, HRV, and steps via Health Connect when available. Demo data fills the gap.",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            OnboardingStep.MEDICATION_INTRO -> {
                Text("Medications", style = MaterialTheme.typography.headlineMedium)
                Text(
                    "Configure doses under You → Medication. Daily flags reset at midnight with LifeEngine.",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            OnboardingStep.DONE -> {
                Text("You're set${if (state.displayName.isNotBlank()) ", ${state.displayName}" else ""}.",
                    style = MaterialTheme.typography.headlineMedium)
            }
        }
        Spacer(Modifier.height(24.dp))
        Button(
            onClick = { onIntent(OnboardingIntent.Next) },
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(
                containerColor = LookAfterColors.AccentPrimary,
                contentColor = LookAfterColors.AccentOnPrimary,
            ),
        ) {
            Text(if (state.step == OnboardingStep.MEDICATION_INTRO) "Enter Look After" else "Continue")
        }
        TextButton(onClick = { onIntent(OnboardingIntent.Skip) }, modifier = Modifier.fillMaxWidth()) {
            Text("Skip for now")
        }
    }
}
