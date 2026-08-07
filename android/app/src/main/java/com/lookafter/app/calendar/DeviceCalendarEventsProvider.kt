package com.lookafter.app.calendar

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.provider.CalendarContract
import androidx.core.content.ContextCompat
import com.lookafter.core.calendar.CalendarEvent
import com.lookafter.core.calendar.CalendarEventsProvider
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Reads device calendars via [CalendarContract] when READ_CALENDAR is granted.
 * Returns empty list when permission is missing or the provider is unavailable.
 */
class DeviceCalendarEventsProvider(
    private val context: Context,
) : CalendarEventsProvider {

    override suspend fun eventsForDay(day: LocalDate, zone: ZoneId): List<CalendarEvent> =
        withContext(Dispatchers.IO) {
            if (!hasPermission()) return@withContext emptyList()
            val startMs = day.atStartOfDay(zone).toInstant().toEpochMilli()
            val endMs = day.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
            val projection = arrayOf(
                CalendarContract.Instances.EVENT_ID,
                CalendarContract.Instances.TITLE,
                CalendarContract.Instances.BEGIN,
                CalendarContract.Instances.END,
                CalendarContract.Instances.ALL_DAY,
            )
            val uri = CalendarContract.Instances.CONTENT_URI.buildUpon()
                .appendPath(startMs.toString())
                .appendPath(endMs.toString())
                .build()
            val out = mutableListOf<CalendarEvent>()
            runCatching {
                context.contentResolver.query(
                    uri,
                    projection,
                    null,
                    null,
                    "${CalendarContract.Instances.BEGIN} ASC",
                )?.use { cursor ->
                    val idIdx = cursor.getColumnIndex(CalendarContract.Instances.EVENT_ID)
                    val titleIdx = cursor.getColumnIndex(CalendarContract.Instances.TITLE)
                    val beginIdx = cursor.getColumnIndex(CalendarContract.Instances.BEGIN)
                    val endIdx = cursor.getColumnIndex(CalendarContract.Instances.END)
                    val allDayIdx = cursor.getColumnIndex(CalendarContract.Instances.ALL_DAY)
                    while (cursor.moveToNext()) {
                        val id = cursor.getLong(idIdx).toString()
                        val title = cursor.getString(titleIdx) ?: "Event"
                        val begin = Instant.ofEpochMilli(cursor.getLong(beginIdx))
                        val end = if (endIdx >= 0 && !cursor.isNull(endIdx)) {
                            Instant.ofEpochMilli(cursor.getLong(endIdx))
                        } else {
                            null
                        }
                        val allDay = allDayIdx >= 0 && cursor.getInt(allDayIdx) == 1
                        out += CalendarEvent(
                            id = id,
                            title = title,
                            start = begin,
                            end = end,
                            isAllDay = allDay,
                        )
                    }
                }
            }
            out
        }

    fun hasPermission(): Boolean =
        ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.READ_CALENDAR,
        ) == PackageManager.PERMISSION_GRANTED
}
