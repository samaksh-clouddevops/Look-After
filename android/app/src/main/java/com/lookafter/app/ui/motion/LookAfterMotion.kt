package com.lookafter.app.ui.motion

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer

/** Shared motion tokens — calm iOS-like ease (not snappy Material defaults). */
object LookAfterMotion {
    const val shortMs = 220
    const val mediumMs = 320
    const val longMs = 420

    val fadeSlideIn = fadeIn(tween(mediumMs, easing = FastOutSlowInEasing)) +
        slideInVertically(tween(mediumMs, easing = FastOutSlowInEasing)) { it / 12 }

    val fadeSlideOut = fadeOut(tween(shortMs, easing = FastOutSlowInEasing)) +
        slideOutVertically(tween(shortMs, easing = FastOutSlowInEasing)) { it / 16 }
}

/** Fade+rise entrance used when a tab/surface first appears. */
@Composable
fun CalmEntrance(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    val visible = remember { MutableTransitionState(false) }
    LaunchedEffect(Unit) { visible.targetState = true }
    AnimatedVisibility(
        visibleState = visible,
        enter = LookAfterMotion.fadeSlideIn,
        exit = LookAfterMotion.fadeSlideOut,
        modifier = modifier,
    ) {
        content()
    }
}

/** Cross-fade tab body when destination changes. */
@Composable
fun <T> CalmAnimatedContent(
    targetState: T,
    modifier: Modifier = Modifier,
    content: @Composable (T) -> Unit,
) {
    AnimatedContent(
        targetState = targetState,
        modifier = modifier,
        transitionSpec = {
            (
                fadeIn(tween(LookAfterMotion.mediumMs, easing = FastOutSlowInEasing)) +
                    slideInVertically(tween(LookAfterMotion.mediumMs)) { it / 20 }
                ) togetherWith (
                fadeOut(tween(LookAfterMotion.shortMs)) +
                    slideOutVertically(tween(LookAfterMotion.shortMs)) { -it / 24 }
                )
        },
        label = "lookafter-tab",
        content = { content(it) },
    )
}

/** Subtle press scale for primary cards/buttons. */
@Composable
fun calmPressScale(pressed: Boolean): Modifier =
    Modifier.graphicsLayer {
        val s = if (pressed) 0.98f else 1f
        scaleX = s
        scaleY = s
        alpha = if (pressed) 0.96f else 1f
    }
