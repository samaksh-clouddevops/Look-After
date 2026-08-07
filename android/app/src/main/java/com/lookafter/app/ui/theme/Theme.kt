package com.lookafter.app.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext

private val LightColorScheme = lightColorScheme(
    primary = LookAfterColors.Accent,
    onPrimary = LookAfterColors.LightSurface,
    primaryContainer = LookAfterColors.AccentSoft,
    onPrimaryContainer = LookAfterColors.Accent,
    secondary = LookAfterColors.Flexible,
    onSecondary = LookAfterColors.LightSurface,
    background = LookAfterColors.LightBackground,
    onBackground = LookAfterColors.LightOnBackground,
    surface = LookAfterColors.LightSurface,
    onSurface = LookAfterColors.LightOnSurface,
    surfaceVariant = LookAfterColors.LightSurfaceSecondary,
    onSurfaceVariant = LookAfterColors.LightMuted,
    outline = LookAfterColors.LightOutline,
)

private val DarkColorScheme = darkColorScheme(
    primary = LookAfterColors.AccentOnDark,
    onPrimary = LookAfterColors.DarkBackground,
    primaryContainer = LookAfterColors.DarkSurfaceSecondary,
    onPrimaryContainer = LookAfterColors.AccentOnDark,
    secondary = LookAfterColors.Flexible,
    onSecondary = LookAfterColors.DarkOnSurface,
    background = LookAfterColors.DarkBackground,
    onBackground = LookAfterColors.DarkOnBackground,
    surface = LookAfterColors.DarkSurface,
    onSurface = LookAfterColors.DarkOnSurface,
    surfaceVariant = LookAfterColors.DarkSurfaceSecondary,
    onSurfaceVariant = LookAfterColors.DarkMuted,
    outline = LookAfterColors.DarkOutline,
)

@Composable
fun LookAfterTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    /** Dynamic color is intentionally off — brand indigo is part of the identity. */
    dynamicColor: Boolean = false,
    content: @Composable () -> Unit,
) {
    val colorScheme: ColorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = LookAfterTypography,
        content = content,
    )
}
