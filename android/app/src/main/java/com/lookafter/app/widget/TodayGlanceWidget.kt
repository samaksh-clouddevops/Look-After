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
import androidx.glance.appwidget.action.actionSendBroadcast
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
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

    fun openApp(context: Context, target: String): Intent =
        Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_TARGET, target)
        }
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
                    readiness = tick?.world?.healthReadiness,
                    hasHero = !tick?.decision?.heroTaskId.isNullOrBlank(),
                )
            }
        }
    }
}

@Composable
private fun WidgetContent(
    hero: String,
    reason: String,
    open: Int,
    readiness: Double?,
    hasHero: Boolean,
) {
    val context = LocalContext.current
    val openToday = LookAfterDeepLink.openApp(context, LookAfterDeepLink.TARGET_TODAY)
    val openFocus = LookAfterDeepLink.openApp(context, LookAfterDeepLink.TARGET_FOCUS)
    val openBrain = LookAfterDeepLink.openApp(context, LookAfterDeepLink.TARGET_BRAIN)
    val completeHero = Intent(context, WidgetActionReceiver::class.java).apply {
        action = WidgetActionReceiver.ACTION_COMPLETE_HERO
    }

    val primary = ColorProvider(day = LookAfterColors.LightTextPrimary, night = LookAfterColors.DarkTextPrimary)
    val secondary = ColorProvider(day = LookAfterColors.LightTextSecondary, night = LookAfterColors.DarkTextSecondary)
    val muted = ColorProvider(day = LookAfterColors.LightTextMuted, night = LookAfterColors.DarkTextMuted)
    val accent = ColorProvider(day = LookAfterColors.AccentPrimary, night = LookAfterColors.AccentOnDark)

    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(ColorProvider(day = LookAfterColors.LightSurface, night = LookAfterColors.DarkSurface))
            .padding(14.dp),
        verticalAlignment = Alignment.Vertical.Top,
    ) {
        Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.Vertical.CenterVertically) {
            Text(
                text = "Today",
                style = TextStyle(color = accent, fontSize = 12.sp, fontWeight = FontWeight.Bold),
                modifier = GlanceModifier.defaultWeight(),
            )
            Text(text = "$open open", style = TextStyle(color = muted, fontSize = 11.sp))
        }

        Spacer(GlanceModifier.height(6.dp))

        Column(
            modifier = GlanceModifier
                .fillMaxWidth()
                .clickable(actionStartActivity(openToday)),
        ) {
            Text(
                text = hero,
                style = TextStyle(color = primary, fontSize = 16.sp, fontWeight = FontWeight.Bold),
                maxLines = 2,
            )
            Spacer(GlanceModifier.height(4.dp))
            Text(
                text = reason,
                style = TextStyle(color = secondary, fontSize = 12.sp),
                maxLines = 2,
            )
            if (readiness != null) {
                Spacer(GlanceModifier.height(4.dp))
                Text(
                    text = "Readiness " + "%.0f".format(readiness * 100) + "%",
                    style = TextStyle(color = muted, fontSize = 11.sp),
                )
            }
        }

        Spacer(GlanceModifier.height(10.dp))

        Row(modifier = GlanceModifier.fillMaxWidth()) {
            Text(
                text = "Focus",
                style = TextStyle(color = accent, fontSize = 13.sp, fontWeight = FontWeight.Bold),
                modifier = GlanceModifier
                    .defaultWeight()
                    .clickable(actionStartActivity(openFocus))
                    .padding(vertical = 4.dp),
            )
            Text(
                text = "Done",
                style = TextStyle(
                    color = if (hasHero) accent else muted,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold,
                ),
                modifier = GlanceModifier
                    .defaultWeight()
                    .clickable(actionSendBroadcast(completeHero))
                    .padding(vertical = 4.dp),
            )
            Text(
                text = "Brain",
                style = TextStyle(color = accent, fontSize = 13.sp, fontWeight = FontWeight.Bold),
                modifier = GlanceModifier
                    .defaultWeight()
                    .clickable(actionStartActivity(openBrain))
                    .padding(vertical = 4.dp),
            )
        }
    }
}

class TodayGlanceWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = TodayGlanceWidget()
}
