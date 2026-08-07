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
import androidx.compose.foundation.text.KeyboardOptions
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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import com.lookafter.app.ui.components.ElevatedSurfaceCard
import com.lookafter.app.ui.components.SectionHeader
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens

@Composable
fun PrivacySettingsScreen(
    appVersion: String = "0.1.0",
    llmConfigured: Boolean,
    firebaseAvailable: Boolean,
    onExport: () -> Unit,
    onExportToFolder: () -> Unit = onExport,
    onImport: () -> Unit = {},
    onFactoryReset: () -> Unit,
    onSignInEmail: (email: String, password: String) -> Unit,
    onOpenPrivacyPolicy: () -> Unit,
    onBack: () -> Unit,
    statusMessage: String? = null,
    modifier: Modifier = Modifier,
) {
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var confirmReset by remember { mutableStateOf(false) }
    var confirmImport by remember { mutableStateOf(false) }

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
                title = "Privacy & data",
                subtitle = "v$appVersion · local-first by default",
            )
        }
        if (!statusMessage.isNullOrBlank()) {
            item {
                Text(statusMessage, color = LookAfterColors.AccentPrimary, style = MaterialTheme.typography.labelMedium)
            }
        }
        item {
            ElevatedSurfaceCard {
                Text("Backup", style = MaterialTheme.typography.labelMedium, color = LookAfterColors.AccentPrimary)
                Text(
                    "Export LifeState JSON via share sheet or save to a folder. Import replaces this device's board.",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                )
                Button(
                    onClick = onExport,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = LookAfterDimens.spacingSM),
                    colors = ButtonDefaults.buttonColors(containerColor = LookAfterColors.AccentPrimary),
                ) { Text("Export & share") }
                TextButton(
                    onClick = onExportToFolder,
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Save to Files…") }
                if (!confirmImport) {
                    TextButton(
                        onClick = { confirmImport = true },
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text("Import backup…") }
                } else {
                    Text(
                        "Import will replace tasks, meds, and queues on this device.",
                        style = MaterialTheme.typography.bodyLarge,
                        color = LookAfterColors.Warning,
                        modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                    )
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = LookAfterDimens.spacingSM),
                        horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
                    ) {
                        TextButton(
                            onClick = { confirmImport = false },
                            modifier = Modifier.weight(1f),
                        ) { Text("Cancel") }
                        Button(
                            onClick = {
                                confirmImport = false
                                onImport()
                            },
                            modifier = Modifier.weight(1f),
                            colors = ButtonDefaults.buttonColors(containerColor = LookAfterColors.AccentPrimary),
                        ) { Text("Choose file") }
                    }
                }
            }
        }
        item {
            ElevatedSurfaceCard {
                Text("Integrations", style = MaterialTheme.typography.labelMedium, color = LookAfterColors.AccentPrimary)
                Text(
                    "LLM planner: ${if (llmConfigured) "configured" else "offline only"}\n" +
                        "Firebase: ${if (firebaseAvailable) "SDK present" else "not packaged"}",
                    style = MaterialTheme.typography.bodyLarge,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                )
            }
        }
        if (firebaseAvailable) {
            item {
                ElevatedSurfaceCard {
                    Text("Email sign-in", style = MaterialTheme.typography.labelMedium, color = LookAfterColors.AccentPrimary)
                    OutlinedTextField(
                        value = email,
                        onValueChange = { email = it },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = LookAfterDimens.spacingSM),
                        label = { Text("Email") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                    )
                    OutlinedTextField(
                        value = password,
                        onValueChange = { password = it },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = LookAfterDimens.spacingSM),
                        label = { Text("Password") },
                        singleLine = true,
                        visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    )
                    Button(
                        onClick = { onSignInEmail(email.trim(), password) },
                        enabled = email.contains("@") && password.length >= 6,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = LookAfterDimens.spacingSM),
                        colors = ButtonDefaults.buttonColors(containerColor = LookAfterColors.AccentPrimary),
                    ) { Text("Sign in with email") }
                }
            }
        }
        item {
            ElevatedSurfaceCard {
                Text("Privacy policy", style = MaterialTheme.typography.labelMedium, color = LookAfterColors.AccentPrimary)
                Text(
                    "How Look After handles tasks, health, camera, and optional cloud services.",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                )
                TextButton(onClick = onOpenPrivacyPolicy) { Text("View privacy policy") }
            }
        }
        item {
            ElevatedSurfaceCard {
                Text("Factory reset", style = MaterialTheme.typography.labelMedium, color = LookAfterColors.Error)
                Text(
                    "Erase tasks, meds, focus, inbox, and onboarding on this device. Cannot be undone.",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                )
                if (!confirmReset) {
                    Button(
                        onClick = { confirmReset = true },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = LookAfterDimens.spacingSM),
                        colors = ButtonDefaults.buttonColors(containerColor = LookAfterColors.Error),
                    ) { Text("Reset this device…") }
                } else {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = LookAfterDimens.spacingSM),
                        horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
                    ) {
                        TextButton(onClick = { confirmReset = false }, modifier = Modifier.weight(1f)) {
                            Text("Cancel")
                        }
                        Button(
                            onClick = {
                                confirmReset = false
                                onFactoryReset()
                            },
                            modifier = Modifier.weight(1f),
                            colors = ButtonDefaults.buttonColors(containerColor = LookAfterColors.Error),
                        ) { Text("Erase now") }
                    }
                }
            }
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
