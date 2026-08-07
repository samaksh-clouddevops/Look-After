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
    primary = LookAfterColors.AccentPrimary,
    onPrimary = LookAfterColors.AccentOnPrimary,
    primaryContainer = LookAfterColors.AccentSoft,
    onPrimaryContainer = LookAfterColors.AccentPressed,
    secondary = LookAfterColors.Focus,
    onSecondary = LookAfterColors.LightTextPrimary,
    tertiary = LookAfterColors.Health,
    onTertiary = LookAfterColors.LightTextPrimary,
    background = LookAfterColors.LightBackground,
    onBackground = LookAfterColors.LightTextPrimary,
    surface = LookAfterColors.LightSurface,
    onSurface = LookAfterColors.LightTextPrimary,
    surfaceVariant = LookAfterColors.LightSurfaceElevated,
    onSurfaceVariant = LookAfterColors.LightTextSecondary,
    outline = LookAfterColors.LightBorder,
    outlineVariant = LookAfterColors.LightDivider,
    error = LookAfterColors.Error,
    onError = LookAfterColors.AccentOnPrimary,
)

private val DarkColorScheme = darkColorScheme(
    primary = LookAfterColors.AccentOnDark,
    onPrimary = LookAfterColors.DarkBackground,
    primaryContainer = LookAfterColors.DarkSurfaceElevated,
    onPrimaryContainer = LookAfterColors.AccentOnDark,
    secondary = LookAfterColors.Focus,
    onSecondary = LookAfterColors.DarkTextPrimary,
    tertiary = LookAfterColors.Health,
    onTertiary = LookAfterColors.DarkTextPrimary,
    background = LookAfterColors.DarkBackground,
    onBackground = LookAfterColors.DarkTextPrimary,
    surface = LookAfterColors.DarkSurface,
    onSurface = LookAfterColors.DarkTextPrimary,
    surfaceVariant = LookAfterColors.DarkSurfaceElevated,
    onSurfaceVariant = LookAfterColors.DarkTextSecondary,
    outline = LookAfterColors.DarkBorder,
    outlineVariant = LookAfterColors.DarkDivider,
    error = LookAfterColors.Error,
    onError = LookAfterColors.DarkTextPrimary,
)

@Composable
fun LookAfterTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    /** Dynamic Material You off — brand green is part of the identity (matches iOS). */
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
