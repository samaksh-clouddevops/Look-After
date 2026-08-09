package com.lookafter.app.webrtc

import android.view.ViewGroup
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import org.webrtc.EglBase
import org.webrtc.SurfaceViewRenderer

/**
 * Compose wrappers around WebRTC [SurfaceViewRenderer].
 * Call [onReady] so the active [NativeWebRtcSession] can attach sinks.
 */
@Composable
fun WebRtcLocalPreview(
    eglContext: EglBase.Context?,
    onReady: (SurfaceViewRenderer) -> Unit,
    modifier: Modifier = Modifier,
    label: String = "You",
) {
    WebRtcSurface(
        eglContext = eglContext,
        mirror = true,
        onReady = onReady,
        label = label,
        modifier = modifier,
    )
}

@Composable
fun WebRtcRemoteView(
    eglContext: EglBase.Context?,
    onReady: (SurfaceViewRenderer) -> Unit,
    modifier: Modifier = Modifier,
    label: String = "Partner",
) {
    WebRtcSurface(
        eglContext = eglContext,
        mirror = false,
        onReady = onReady,
        label = label,
        modifier = modifier,
    )
}

@Composable
private fun WebRtcSurface(
    eglContext: EglBase.Context?,
    mirror: Boolean,
    onReady: (SurfaceViewRenderer) -> Unit,
    label: String,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val renderer = remember {
        SurfaceViewRenderer(context).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            setEnableHardwareScaler(true)
            setMirror(mirror)
        }
    }
    DisposableEffect(eglContext) {
        if (eglContext != null) {
            runCatching {
                renderer.init(eglContext, null)
                onReady(renderer)
            }
        }
        onDispose {
            runCatching { renderer.release() }
        }
    }
    Box(
        modifier = modifier
            .fillMaxWidth()
            .aspectRatio(3f / 4f)
            .clip(RoundedCornerShape(LookAfterDimens.radiusMD))
            .background(MaterialTheme.colorScheme.surfaceVariant),
    ) {
        if (eglContext != null) {
            AndroidView(factory = { renderer }, modifier = Modifier.fillMaxSize())
        } else {
            Text(
                "WebRTC preview unavailable",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.align(Alignment.Center).padding(LookAfterDimens.spacingMD),
            )
        }
        Text(
            label,
            style = MaterialTheme.typography.labelMedium,
            color = LookAfterColors.AccentOnPrimary,
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(LookAfterDimens.spacingSM)
                .background(LookAfterColors.AccentPrimary.copy(alpha = 0.85f), RoundedCornerShape(6.dp))
                .padding(horizontal = 8.dp, vertical = 4.dp),
        )
    }
}
