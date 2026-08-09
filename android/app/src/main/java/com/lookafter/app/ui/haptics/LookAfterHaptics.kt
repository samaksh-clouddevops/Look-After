package com.lookafter.app.ui.haptics

import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalView

/**
 * Light haptics for Today complete / park.
 * No-ops when disabled via preferences.
 */
class LookAfterHaptics(
    private val view: View,
    private val enabled: () -> Boolean,
) {
    fun tick() {
        if (!enabled()) return
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            HapticFeedbackConstants.CONFIRM
        } else {
            HapticFeedbackConstants.KEYBOARD_TAP
        }
        view.performHapticFeedback(type)
    }

    fun soft() {
        if (!enabled()) return
        view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
    }
}

@Composable
fun rememberLookAfterHaptics(enabled: () -> Boolean): LookAfterHaptics {
    val view = LocalView.current
    return remember(view) { LookAfterHaptics(view, enabled) }
}
