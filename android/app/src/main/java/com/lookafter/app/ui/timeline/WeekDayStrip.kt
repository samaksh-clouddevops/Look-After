package com.lookafter.app.ui.timeline

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.core.today.TodayBoard
import java.time.LocalDate
import java.time.format.TextStyle
import java.util.Locale

/** Horizontal Mon–Sun scrubber with open-count dots. */
@Composable
fun WeekDayStrip(
    pills: List<TodayBoard.DayPill>,
    onSelect: (LocalDate) -> Unit,
    onShiftWeek: (deltaWeeks: Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "‹",
                style = MaterialTheme.typography.titleLarge,
                color = LookAfterColors.AccentPrimary,
                modifier = Modifier
                    .clickable { onShiftWeek(-1) }
                    .padding(8.dp),
            )
            Text(
                text = weekLabel(pills),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = "›",
                style = MaterialTheme.typography.titleLarge,
                color = LookAfterColors.AccentPrimary,
                modifier = Modifier
                    .clickable { onShiftWeek(1) }
                    .padding(8.dp),
            )
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            pills.forEach { pill ->
                DayPillCell(pill = pill, onClick = { onSelect(pill.day) })
            }
        }
    }
}

@Composable
private fun DayPillCell(pill: TodayBoard.DayPill, onClick: () -> Unit) {
    val bg = when {
        pill.isSelected -> LookAfterColors.AccentPrimary
        pill.isToday -> LookAfterColors.AccentSoft
        else -> MaterialTheme.colorScheme.surface
    }
    val fg = when {
        pill.isSelected -> LookAfterColors.AccentOnPrimary
        else -> MaterialTheme.colorScheme.onSurface
    }
    val border = if (pill.isToday && !pill.isSelected) {
        Modifier.border(1.dp, LookAfterColors.AccentPrimary, RoundedCornerShape(LookAfterDimens.radiusMD))
    } else {
        Modifier
    }
    Column(
        modifier = Modifier
            .width(48.dp)
            .clip(RoundedCornerShape(LookAfterDimens.radiusMD))
            .then(border)
            .background(bg)
            .clickable(onClick = onClick)
            .padding(vertical = 8.dp, horizontal = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = pill.day.dayOfWeek.getDisplayName(TextStyle.SHORT, Locale.getDefault()).take(2),
            style = MaterialTheme.typography.labelSmall,
            color = fg.copy(alpha = 0.85f),
        )
        Text(
            text = pill.day.dayOfMonth.toString(),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            color = fg,
        )
        val dots = (pill.openCount).coerceAtMost(3)
        Row(
            horizontalArrangement = Arrangement.spacedBy(2.dp),
            modifier = Modifier.padding(top = 4.dp),
        ) {
            if (dots == 0 && pill.doneCount > 0) {
                Box(
                    Modifier
                        .size(4.dp)
                        .clip(CircleShape)
                        .background(if (pill.isSelected) fg.copy(alpha = 0.5f) else LookAfterColors.Success),
                )
            } else {
                repeat(dots) {
                    Box(
                        Modifier
                            .size(4.dp)
                            .clip(CircleShape)
                            .background(if (pill.isSelected) fg else LookAfterColors.AccentPrimary),
                    )
                }
            }
        }
    }
}

private fun weekLabel(pills: List<TodayBoard.DayPill>): String {
    if (pills.isEmpty()) return ""
    val a = pills.first().day
    val b = pills.last().day
    val fmt = java.time.format.DateTimeFormatter.ofPattern("MMM d")
    return "${a.format(fmt)} – ${b.format(fmt)}"
}
