package com.lookafter.core.notifications

import java.time.LocalTime
import java.time.ZoneId
import java.time.Instant
import kotlinx.serialization.Serializable

/**
 * User-facing notification preferences (serializable for DataStore / SharedPreferences).
 * Applied by [NotificationPolicy.plan].
 */
@Serializable
data class NotificationPreferences(
    val medicationsEnabled: Boolean = true,
    val anchoredEnabled: Boolean = true,
    val briefingEnabled: Boolean = true,
    val focusCompleteEnabled: Boolean = true,
    /** Lead time before anchored starts. */
    val anchoredLeadMinutes: Int = 15,
    val suppressDuringFocus: Boolean = true,
    val quietHoursEnabled: Boolean = true,
    /** Hour 0–23 local. */
    val quietHoursStartHour: Int = 22,
    val quietHoursEndHour: Int = 7,
    /** Soft haptic feedback on complete/park in Today. */
    val hapticsEnabled: Boolean = true,
) {
    fun toPolicyConfig(): NotificationPolicyConfig = NotificationPolicyConfig(
        medicationsEnabled = medicationsEnabled,
        anchoredEnabled = anchoredEnabled,
        briefingEnabled = briefingEnabled,
        focusCompleteEnabled = focusCompleteEnabled,
        anchoredLeadMinutes = anchoredLeadMinutes.coerceIn(5, 60),
        quietHoursEnabled = quietHoursEnabled,
        quietHoursStartHour = quietHoursStartHour.coerceIn(0, 23),
        quietHoursEndHour = quietHoursEndHour.coerceIn(0, 23),
        suppressDuringFocus = suppressDuringFocus,
    )

    fun quietWindowLabel(): String {
        if (!quietHoursEnabled) return "Off"
        return "%02d:00–%02d:00".format(quietHoursStartHour, quietHoursEndHour)
    }

    companion object {
        val DEFAULT = NotificationPreferences()
    }
}

/** Returns true if [instant] falls inside quiet hours in [zone]. */
fun NotificationPreferences.isInQuietHours(
    instant: Instant,
    zone: ZoneId = ZoneId.systemDefault(),
): Boolean {
    if (!quietHoursEnabled) return false
    val t = instant.atZone(zone).toLocalTime()
    val start = LocalTime.of(quietHoursStartHour.coerceIn(0, 23), 0)
    val end = LocalTime.of(quietHoursEndHour.coerceIn(0, 23), 0)
    return if (start <= end) {
        // same-day window (rare)
        !t.isBefore(start) && t.isBefore(end)
    } else {
        // overnight e.g. 22:00–07:00
        !t.isBefore(start) || t.isBefore(end)
    }
}
