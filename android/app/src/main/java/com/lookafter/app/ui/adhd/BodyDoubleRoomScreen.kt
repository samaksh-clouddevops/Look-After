package com.lookafter.app.ui.adhd

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.lookafter.app.ui.components.ElevatedSurfaceCard
import com.lookafter.app.ui.components.SectionHeader
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.app.webrtc.WebRtcLocalPreview
import com.lookafter.app.webrtc.WebRtcRemoteView
import com.lookafter.core.adhd.BodyDoubleRoomPhase
import com.lookafter.core.adhd.BodyDoubleRoomState
import com.lookafter.core.adhd.BodyDoubleSessionSummary
import org.webrtc.EglBase
import org.webrtc.SurfaceViewRenderer

/** Multi-person body-double room UI (C3 session controls). */
@Composable
fun BodyDoubleRoomScreen(
    room: BodyDoubleRoomState,
    webRtcStateLabel: String = "new",
    webRtcBackendLabel: String = "simulator",
    signalingLabel: String = "local-file",
    webRtcNative: Boolean = false,
    eglContext: EglBase.Context? = null,
    videoEnabled: Boolean = true,
    audioEnabled: Boolean = false,
    autoFocusOnConnect: Boolean = true,
    statusMessage: String? = null,
    lastSummary: BodyDoubleSessionSummary? = null,
    onAttachLocalRenderer: (SurfaceViewRenderer) -> Unit = {},
    onAttachRemoteRenderer: (SurfaceViewRenderer) -> Unit = {},
    onVideoEnabledChange: (Boolean) -> Unit = {},
    onAudioEnabledChange: (Boolean) -> Unit = {},
    onAutoFocusChange: (Boolean) -> Unit = {},
    onReconnect: () -> Unit = {},
    onClearSummary: () -> Unit = {},
    onCreate: (displayName: String) -> Unit,
    onJoin: (roomId: String, displayName: String) -> Unit,
    onDemoConnect: () -> Unit,
    onLeave: () -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var name by remember { mutableStateOf("You") }
    var code by remember { mutableStateOf(room.roomId.orEmpty()) }

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = LookAfterDimens.screenHorizontal)
            .padding(vertical = LookAfterDimens.spacingLG),
        verticalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingMD),
    ) {
        SectionHeader(
            title = "Body double room",
            subtitle = if (webRtcNative) "Native WebRTC · STUN/TURN" else "Shared focus presence",
        )

        lastSummary?.let { summary ->
            ElevatedSurfaceCard {
                Text("Session complete", style = MaterialTheme.typography.labelMedium, color = LookAfterColors.AccentPrimary)
                Text(
                    "${summary.durationLabel} · ${summary.peerCount} peer(s)",
                    style = MaterialTheme.typography.titleLarge,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXXS),
                )
                Text(
                    buildString {
                        append("Room ${summary.roomId.ifBlank { "—" }}")
                        append(" · ${summary.webRtcBackend} · ${summary.signaling}")
                        if (summary.reachedConnected) append(" · connected")
                        if (summary.focusStarted) append(" · focus started")
                        if (summary.peerNames.isNotEmpty()) {
                            append("\n")
                            append(summary.peerNames.joinToString())
                        }
                    },
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                )
                TextButton(onClick = onClearSummary) { Text("Dismiss summary") }
            }
        }

        if (!statusMessage.isNullOrBlank()) {
            Text(
                statusMessage,
                style = MaterialTheme.typography.labelMedium,
                color = if (room.phase == BodyDoubleRoomPhase.FAILED || webRtcStateLabel == "failed") {
                    LookAfterColors.Error
                } else {
                    LookAfterColors.AccentPrimary
                },
            )
        }

        if (room.isActive && room.phase != BodyDoubleRoomPhase.FAILED) {
            ElevatedSurfaceCard {
                Text("Room", style = MaterialTheme.typography.labelMedium, color = LookAfterColors.AccentPrimary)
                Text(
                    room.roomId ?: "—",
                    style = MaterialTheme.typography.headlineMedium,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXXS),
                )
                Text(
                    "Phase: ${room.phase.name.lowercase()} · peers ${room.peers.size}",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                )
                Text(
                    "WebRTC: $webRtcStateLabel · $webRtcBackendLabel · signal $signalingLabel",
                    style = MaterialTheme.typography.labelMedium,
                    color = LookAfterColors.AccentPrimary,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXXS),
                )
                room.remotePeers.forEach { peer ->
                    Text(
                        "· ${peer.displayName}${if (peer.isConnected) " ✓" else " …"}",
                        style = MaterialTheme.typography.bodyLarge,
                    )
                }
            }
            ElevatedSurfaceCard {
                Text("Session controls", style = MaterialTheme.typography.labelMedium, color = LookAfterColors.AccentPrimary)
                SessionToggleRow("Camera", videoEnabled, onVideoEnabledChange)
                SessionToggleRow("Microphone", audioEnabled, onAudioEnabledChange)
                SessionToggleRow("Start focus when connected", autoFocusOnConnect, onAutoFocusChange)
            }
            if (webRtcNative && eglContext != null && videoEnabled) {
                WebRtcLocalPreview(
                    eglContext = eglContext,
                    onReady = onAttachLocalRenderer,
                    modifier = Modifier.fillMaxWidth(),
                )
                WebRtcRemoteView(
                    eglContext = eglContext,
                    onReady = onAttachRemoteRenderer,
                    modifier = Modifier.fillMaxWidth(),
                )
            } else if (!videoEnabled) {
                ElevatedSurfaceCard {
                    Text("Camera muted", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "Your video track is off.",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            } else {
                CameraBodyDouble(
                    emergency = false,
                    elapsedActiveSeconds = 0L,
                    enabled = room.useCamera,
                    modifier = Modifier.fillMaxWidth(),
                )
                BodyDoublePresencePanel(
                    emergency = false,
                    elapsedActiveSeconds = 30L,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            if (room.phase == BodyDoubleRoomPhase.WAITING || room.phase == BodyDoubleRoomPhase.CONNECTING) {
                Button(
                    onClick = onDemoConnect,
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(containerColor = LookAfterColors.AccentPrimary),
                ) { Text("Simulate partner join (demo)") }
            }
            if (webRtcStateLabel == "failed" || room.phase == BodyDoubleRoomPhase.RECONNECTING) {
                Button(
                    onClick = onReconnect,
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(containerColor = LookAfterColors.Focus),
                ) { Text("Reconnect") }
            }
            Button(
                onClick = onLeave,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = LookAfterColors.Error),
            ) { Text("Leave room") }
        } else if (room.phase != BodyDoubleRoomPhase.ENDED || lastSummary == null) {
            ElevatedSurfaceCard {
                Text(
                    "Create a room and share the code, or join a partner.",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = LookAfterDimens.spacingSM),
                    label = { Text("Display name") },
                    singleLine = true,
                )
                OutlinedTextField(
                    value = code,
                    onValueChange = { code = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = LookAfterDimens.spacingSM),
                    label = { Text("Room code (to join)") },
                    singleLine = true,
                )
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = LookAfterDimens.spacingSM),
                    horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
                ) {
                    Button(
                        onClick = { onCreate(name.trim().ifEmpty { "You" }) },
                        modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.buttonColors(containerColor = LookAfterColors.AccentPrimary),
                    ) { Text("Create") }
                    Button(
                        onClick = { onJoin(code.trim(), name.trim().ifEmpty { "You" }) },
                        modifier = Modifier.weight(1f),
                        enabled = code.isNotBlank(),
                    ) { Text("Join") }
                }
            }
            room.lastError?.let {
                Text(it, color = LookAfterColors.Error, style = MaterialTheme.typography.bodyLarge)
            }
        }

        TextButton(onClick = onBack) { Text("Back") }
    }
}

@Composable
private fun SessionToggleRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = LookAfterDimens.spacingSM),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
        Switch(
            checked = checked,
            onCheckedChange = onChange,
            colors = SwitchDefaults.colors(checkedTrackColor = LookAfterColors.AccentPrimary),
        )
    }
}
