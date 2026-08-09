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
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.lookafter.app.ui.components.ElevatedSurfaceCard
import com.lookafter.app.ui.components.SectionHeader
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.app.webrtc.WebRtcLocalPreview
import com.lookafter.app.webrtc.WebRtcRemoteView
import com.lookafter.core.adhd.BodyDoubleRoomPhase
import com.lookafter.core.adhd.BodyDoubleRoomState
import org.webrtc.EglBase
import org.webrtc.SurfaceViewRenderer

/**
 * Multi-person body-double room UI.
 * Native WebRTC video when available; CameraX / presence fallback otherwise.
 */
@Composable
fun BodyDoubleRoomScreen(
    room: BodyDoubleRoomState,
    webRtcStateLabel: String = "new",
    webRtcBackendLabel: String = "simulator",
    webRtcNative: Boolean = false,
    eglContext: EglBase.Context? = null,
    onAttachLocalRenderer: (SurfaceViewRenderer) -> Unit = {},
    onAttachRemoteRenderer: (SurfaceViewRenderer) -> Unit = {},
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
            subtitle = if (webRtcNative) {
                "Native WebRTC · STUN/TURN"
            } else {
                "Shared focus presence · simulator or native"
            },
        )

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
                    "WebRTC: $webRtcStateLabel · backend $webRtcBackendLabel",
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
            if (webRtcNative && eglContext != null) {
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
            } else {
                CameraBodyDouble(
                    emergency = false,
                    elapsedActiveSeconds = 0,
                    enabled = room.useCamera,
                    modifier = Modifier.fillMaxWidth(),
                )
                BodyDoublePresencePanel(
                    emergency = false,
                    elapsedActiveSeconds = 30,
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
            Button(
                onClick = onLeave,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = LookAfterColors.Error),
            ) { Text("Leave room") }
        } else {
            ElevatedSurfaceCard {
                Text(
                    "Create a room and share the code, or join a partner. " +
                        "Demo mode simulates WebRTC connect without a signaling server.",
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
