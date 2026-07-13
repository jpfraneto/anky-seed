package inc.anky.android.core.storage

import java.time.LocalDate
import java.time.temporal.ChronoUnit

/**
 * Position of a calendar day inside the Ankyverse: a repeating 96-day cycle
 * of twelve 8-day regions. Mirrors iOS AnkyverseCalendar
 * (ios/Anky/Core/Storage/AnkyverseCalendar.swift); all values are 1-based.
 */
data class AnkyversePosition(
    val dayIndex: Int,
    val cycleDay: Int,
    val region: Int,
    val dayInRegion: Int,
)

class AnkyverseCalendar(
    private val firstOpenDate: LocalDate,
) {
    fun position(day: LocalDate): AnkyversePosition {
        val rawIndex = ChronoUnit.DAYS.between(firstOpenDate, day).toInt()
        val dayIndex = maxOf(0, rawIndex)
        val cycleDay = dayIndex % CycleLengthDays
        return AnkyversePosition(
            dayIndex = dayIndex + 1,
            cycleDay = cycleDay + 1,
            region = (cycleDay / RegionLengthDays) + 1,
            dayInRegion = (cycleDay % RegionLengthDays) + 1,
        )
    }

    companion object {
        const val CycleLengthDays = 96
        const val RegionLengthDays = 8
    }
}
