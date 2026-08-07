package com.lookafter.app.ui.adhd

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.core.adhd.BodyDoublingPrompts

/**
 * “Video” body-double surface — calm animated presence card.
 * Real camera/WebRTC can replace the procedural panel later; API stays stable.
 */
@Composable
fun BodyDoublePresencePanel(
    emergency: Boolean,
    elapsedActiveSeconds: Long,
    modifier: Modifier = Modifier,
) {
    val infinite = rememberInfiniteTransition(label = "body-double")
    val pulse by infinite.animateFloat(
        initialValue = 0.35f,
        targetValue = 0.75f,
        animationSpec = infiniteRepeatable(
            animation = tween(3200, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "pulse",
    )
    val drift by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(9000, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "drift",
    )

    val c1 = if (emergency) LookAfterColors.Warning.copy(alpha = 0.35f) else LookAfterColors.AccentPrimary.copy(alpha = 0.40f)
    val c2 = if (emergency) Color(0xFF3A1C00) else LookAfterColors.DarkSurfaceElevated
    val c3 = LookAfterColors.Focus.copy(alpha = 0.25f + 0.2f * pulse)

    Column(modifier = modifier.fillMaxWidth()) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(140.dp)
                .clip(RoundedCornerShape(LookAfterDimens.radiusMD))
                .background(
                    Brush.linearGradient(
                        colors = listOf(
                            c1,
                            c2,
                            c3,
                            c2,
                        ),
                        start = androidx.compose.ui.geometry.Offset(drift * 200f, 0f),
                        end = androidx.compose.ui.geometry.Offset(400f - drift * 200f, 280f),
                    ),
                ),
            contentAlignment = Alignment.Center,
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    text = if (emergency) "Emergency presence" else "Body double present",
                    style = MaterialTheme.typography.titleMedium,
                    color = LookAfterColors.DarkTextPrimary,
                )
                Text(
                    text = "Simulated companion · ambient session",
                    style = MaterialTheme.typography.labelMedium,
                    color = LookAfterColors.DarkTextSecondary,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
        }
        Text(
            text = BodyDoublingPrompts.lineFor(elapsedActiveSeconds, emergency),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.padding(top = LookAfterDimens.spacingSM),
        )
    }
}
