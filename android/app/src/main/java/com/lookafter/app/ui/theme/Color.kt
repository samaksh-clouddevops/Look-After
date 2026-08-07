package com.lookafter.app.ui.theme

import androidx.compose.ui.graphics.Color

/**
 * Look After Design System V4 — ported from iOS `DesignSystem.swift`.
 * Calm surfaces, green accent (~5% of UI), semantic life-area colors.
 */
object LookAfterColors {
    // Accent (primary action)
    val AccentPrimary = Color(0xFF5A9E3F)
    val AccentHover = Color(0xFF6BB34A)
    val AccentPressed = Color(0xFF4A852F)
    val AccentOnPrimary = Color(0xFFFFFFFF)
    val AccentSoft = Color(0x1A5A9E3F)

    // Light surfaces
    val LightBackground = Color(0xFFF8F8F6)
    val LightSurface = Color(0xFFFFFFFF)
    val LightSurfaceElevated = Color(0xFFECEEF1)
    val LightTextPrimary = Color(0xFF1C1C1E)
    val LightTextSecondary = Color(0xFF6B7280)
    val LightTextMuted = Color(0xFF9CA3AF)
    val LightBorder = Color(0xFFE5E7EB)
    val LightDivider = Color(0xFFECECEC)

    // Dark surfaces
    val DarkBackground = Color(0xFF111315)
    val DarkSurface = Color(0xFF191C1F)
    val DarkSurfaceElevated = Color(0xFF2B3036)
    val DarkTextPrimary = Color(0xFFF4F4F4)
    val DarkTextSecondary = Color(0xFFB7BDC6)
    val DarkTextMuted = Color(0xFF8D939C)
    val DarkBorder = Color(0xFF31353A)
    val DarkDivider = Color(0xFF2A2E33)

    // Semantic accents
    val Focus = Color(0xFF7DD3FC)
    val Health = Color(0xFF74C69D)
    val Reflection = Color(0xFFB8A1FF)
    val Learning = Color(0xFFF4C95D)
    val Success = Color(0xFF7FD37F)
    val Warning = Color(0xFFF6C453)
    val Error = Color(0xFFF87171)

    // Constraint badges
    val Anchored = Color(0xFFDC2626)
    val Flexible = Color(0xFF2563EB)
    val Fluid = Color(0xFF6B7280)
    val Completed = Success
    val Expired = LightTextMuted

    // Back-compat aliases
    val Accent = AccentPrimary
    val AccentOnDark = Color(0xFFA5D68C)
    val LightOnBackground = LightTextPrimary
    val LightOnSurface = LightTextPrimary
    val LightMuted = LightTextMuted
    val LightOutline = LightBorder
    val LightSurfaceSecondary = LightSurfaceElevated
    val DarkOnBackground = DarkTextPrimary
    val DarkOnSurface = DarkTextPrimary
    val DarkMuted = DarkTextMuted
    val DarkOutline = DarkBorder
    val DarkSurfaceSecondary = DarkSurfaceElevated
}
