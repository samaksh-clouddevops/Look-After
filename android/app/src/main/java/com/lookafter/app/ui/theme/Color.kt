package com.lookafter.app.ui.theme

import androidx.compose.ui.graphics.Color

/**
 * Minimal Look After palette — grouped backgrounds + indigo accent.
 * Mirrors the calm iOS visual identity without copying system Dynamic Color.
 */
object LookAfterColors {
    // Accent (actionable)
    val Accent = Color(0xFF4F46E5) // Indigo 600
    val AccentSoft = Color(0xFFEEF2FF)
    val AccentOnDark = Color(0xFFA5B4FC)

    // Light — grouped background style
    val LightBackground = Color(0xFFF2F2F7) // iOS systemGroupedBackground
    val LightSurface = Color(0xFFFFFFFF)
    val LightSurfaceSecondary = Color(0xFFE5E5EA)
    val LightOnBackground = Color(0xFF1C1C1E)
    val LightOnSurface = Color(0xFF1C1C1E)
    val LightMuted = Color(0xFF8E8E93)
    val LightOutline = Color(0xFFD1D1D6)

    // Dark — grouped background style
    val DarkBackground = Color(0xFF000000)
    val DarkSurface = Color(0xFF1C1C1E)
    val DarkSurfaceSecondary = Color(0xFF2C2C2E)
    val DarkOnBackground = Color(0xFFF2F2F7)
    val DarkOnSurface = Color(0xFFF2F2F7)
    val DarkMuted = Color(0xFF8E8E93)
    val DarkOutline = Color(0xFF3A3A3C)

    // Semantic constraint badges
    val Anchored = Color(0xFFDC2626) // red-600 — immovable
    val Flexible = Color(0xFF2563EB) // blue-600
    val Fluid = Color(0xFF6B7280) // gray-500

    // Status
    val Completed = Color(0xFF16A34A)
    val Expired = Color(0xFF9CA3AF)
}
