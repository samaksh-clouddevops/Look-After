package com.lookafter.app.ui.adhd

import android.Manifest
import android.content.pm.PackageManager
import android.util.Log
import android.view.ViewGroup
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.lookafter.app.ui.theme.LookAfterDimens

/**
 * Front-camera “mirror body double” via CameraX.
 * Falls back to [BodyDoublePresencePanel] when permission denied or CameraX fails.
 * WebRTC multi-person sessions can wrap this preview later.
 */
@Composable
fun CameraBodyDouble(
    emergency: Boolean,
    elapsedActiveSeconds: Long,
    enabled: Boolean = true,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val lifecycleOwner = remember(context) {
        generateSequence(context) { ctx ->
            (ctx as? android.content.ContextWrapper)?.baseContext
        }.filterIsInstance<LifecycleOwner>().firstOrNull()
    }
    var granted by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED,
        )
    }
    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { ok -> granted = ok }

    LaunchedEffect(enabled) {
        if (enabled && !granted) launcher.launch(Manifest.permission.CAMERA)
    }

    if (!enabled || !granted || lifecycleOwner == null) {
        BodyDoublePresencePanel(
            emergency = emergency,
            elapsedActiveSeconds = elapsedActiveSeconds,
            modifier = modifier,
        )
        return
    }

    var bindError by remember { mutableStateOf(false) }

    if (bindError) {
        BodyDoublePresencePanel(
            emergency = emergency,
            elapsedActiveSeconds = elapsedActiveSeconds,
            modifier = modifier,
        )
        return
    }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(180.dp)
            .clip(RoundedCornerShape(LookAfterDimens.radiusMD)),
    ) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { ctx ->
                PreviewView(ctx).apply {
                    layoutParams = ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT,
                    )
                    scaleType = PreviewView.ScaleType.FILL_CENTER
                    implementationMode = PreviewView.ImplementationMode.COMPATIBLE
                }
            },
            update = { previewView ->
                val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
                cameraProviderFuture.addListener({
                    runCatching {
                        val cameraProvider = cameraProviderFuture.get()
                        val preview = Preview.Builder().build().also {
                            it.surfaceProvider = previewView.surfaceProvider
                        }
                        cameraProvider.unbindAll()
                        cameraProvider.bindToLifecycle(
                            lifecycleOwner,
                            CameraSelector.DEFAULT_FRONT_CAMERA,
                            preview,
                        )
                    }.onFailure {
                        Log.w("CameraBodyDouble", "bind failed: ${it.message}")
                        bindError = true
                    }
                }, ContextCompat.getMainExecutor(context))
            },
        )
    }

    DisposableEffect(Unit) {
        onDispose {
            runCatching {
                ProcessCameraProvider.getInstance(context).get().unbindAll()
            }
        }
    }
}
