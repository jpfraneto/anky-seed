package inc.anky.android.core.level.journey

import android.content.SharedPreferences
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/**
 * Minimal session input for journey derivation — decouples the journey from
 * the session index (SessionIndexStore adapts into this at the wiring site).
 */
data class JourneySessionInput(
    val createdAtMs: Long,
    val durationMs: Long,
)

/**
 * One derived reading of the journey. Everything derives from the sealed
 * sessions (the app's store of record for writing) — a day counts when it
 * holds at least one sealed session, and nothing ever resets: a missed day
 * just means the next light comes tomorrow.
 */
data class JourneySnapshot(
    val completedDays: Int = 0, // distinct writing days
    val currentJourneyDay: Int = 1, // day since first writing, 1...96
    val writtenDayIndices: Set<Int> = emptySet(),
    val missedDayIndices: Set<Int> = emptySet(),
    val minutesWritten: Int = 0,
    val writingsCount: Int = 0,
    val streakDays: Int = 0,
) {
    /**
     * The day Anky stands on: the most recently lit one (day 0 before any
     * writing — the sprite waits on the first unlit stone).
     */
    val currentDayIndex: Int
        get() = maxOf(0, minOf(completedDays, JourneySojourn.TotalDays) - 1)
}

/** Pure derivation of the journey from sealed-session timestamps. */
object JourneyState {
    fun derive(
        sessions: List<JourneySessionInput>,
        nowMs: Long = System.currentTimeMillis(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): JourneySnapshot {
        val sessionDays = sessions.map { it.createdAtMs.toLocalDay(zone) }.toSet()

        var currentJourneyDay = 1
        val writtenIndices = mutableSetOf<Int>()
        val missedIndices = mutableSetOf<Int>()
        val firstDay = sessionDays.minOrNull()
        if (firstDay != null) {
            val today = nowMs.toLocalDay(zone)
            val elapsedDays = ChronoUnit.DAYS.between(firstDay, today).toInt()
            currentJourneyDay = minOf(JourneySojourn.TotalDays, maxOf(1, elapsedDays + 1))
            for (index in 0 until currentJourneyDay) {
                val day = firstDay.plusDays(index.toLong())
                if (day in sessionDays) {
                    writtenIndices.add(index)
                } else {
                    missedIndices.add(index)
                }
            }
        }

        val writtenDayIndices = writtenIndices.filter { it in 0 until JourneySojourn.TotalDays }.toSet()
        val missedDayIndices = missedIndices.filter { it in 0 until currentJourneyDay }.toSet()
        return JourneySnapshot(
            completedDays = minOf(JourneySojourn.TotalDays, writtenDayIndices.size),
            currentJourneyDay = currentJourneyDay,
            writtenDayIndices = writtenDayIndices,
            missedDayIndices = missedDayIndices,
            minutesWritten = (sessions.sumOf { it.durationMs } / 60_000L).toInt(),
            writingsCount = sessions.size,
            streakDays = streak(sessionDays, nowMs, zone),
        )
    }

    /**
     * Consecutive written days ending today or yesterday (a day in progress
     * doesn't break its own streak).
     */
    private fun streak(sessionDays: Set<LocalDate>, nowMs: Long, zone: ZoneId): Int {
        val today = nowMs.toLocalDay(zone)
        var cursor = if (today in sessionDays) today else today.minusDays(1)
        var count = 0
        while (cursor in sessionDays) {
            count += 1
            cursor = cursor.minusDays(1)
        }
        return count
    }

    private fun Long.toLocalDay(zone: ZoneId): LocalDate =
        Instant.ofEpochMilli(this).atZone(zone).toLocalDate()
}

/** Celebration ledger (bloom + walk shown once per new day). */
class JourneyCelebrationLedger(private val preferences: SharedPreferences) {
    fun celebratedCount(): Int = preferences.getInt(Key, 0)

    fun markCelebrated(count: Int) {
        preferences.edit().putInt(Key, count).apply()
    }

    companion object {
        const val Key = "anky.journey.celebratedDayCount.v2"
    }
}
