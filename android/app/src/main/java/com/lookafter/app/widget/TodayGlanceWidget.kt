package com.lookafter.app.widget

import android.content.Context
import android.content.Intent
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalContext
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import com.lookafter.app.LookAfterApplication
import com.lookafter.app.MainActivity
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.core.brain.ExecutiveBrainEngine
import com.lookafter.core.health.HealthSummary

/** Deep-link extras understood by [MainActivity] / ViewModel. */
object LookAfterDeepLink {
    const val EXTRA_TARGET = "lookafter_deep_link"
    const val TARGET_TODAY = "today"
    const val TARGET_BRAIN = "brain"
    const val TARGET_FOCUS = "focus"
}

class TodayGlanceWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val app = context.applicationContext as? LookAfterApplication
        val life = app?.lifeEngine?.currentState
        val health = app?.healthRepository?.summary?.value ?: HealthSummary.EMPTY
        val tick = life?.let { ExecutiveBrainEngine.tick(it, health) }
        provideContent {
            GlanceTheme {
                WidgetContent(
                    hero = tick?.decision?.heroTitle ?: "Look After",
                    reason = tick?.decision?.reason ?: "Open the app to load Today",
                    open = tick?.world?.openTaskCount ?: 0,
                )
            }
        }
    }
}

@Composable
private fun WidgetContent(hero: String, reason: String, open: Int) {
    val context = LocalContext.current
    val openToday = Intent(context, MainActivity::class.java).apply {
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        putExtra(LookAfterDeepLink.EXTRA_TARGET, LookAfterDeepLink.TARGET_TODAY)
    }
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(
                ColorProvider(
                    day = LookAfterColors.LightSurface,
                    night = LookAfterColors.DarkSurface,
                ),
            )
            .padding(16.dp)
            .clickable(actionStartActivity(openToday)),
        verticalAlignment = Alignment.Vertical.CenterVertically,
    ) {
        Text(
            text = "Today",
            style = TextStyle(
                color = ColorProvider(
                    day = LookAfterColors.AccentPrimary,
                    night = LookAfterColors.AccentOnDark,
                ),
                fontSize = 12.sp,
            ),
        )
        Text(
            text = hero,
            style = TextStyle(
                color = ColorProvider(
                    day = LookAfterColors.LightTextPrimary,
                    night = LookAfterColors.DarkTextPrimary,
                ),
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
            ),
        )
        Text(
            text = reason,
            style = TextStyle(
                color = ColorProvider(
                    day = LookAfterColors.LightTextSecondary,
                    night = LookAfterColors.DarkTextSecondary,
                ),
                fontSize = 12.sp,
            ),
        )
        Text(
            text = "$open open",
            style = TextStyle(
                color = ColorProvider(
                    day = LookAfterColors.LightTextMuted,
                    night = LookAfterColors.DarkTextMuted,
                ),
                fontSize = 11.sp,
            ),
        )
    }
}

class TodayGlanceWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = TodayGlanceWidget()
}
