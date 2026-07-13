package inc.anky.android.core.gate

import android.content.SharedPreferences
import inc.anky.android.core.storage.SessionSummary
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import kotlin.math.roundToInt

/**
 * A gentle, at-most-once-per-episode offer to lower the daily target after
 * two consecutive missed days (phase-2 §1).
 */
data class AdaptiveTargetOffer(
    /**
     * Local ISO day (yyyy-MM-dd) of the first missed day in the run. Stable
     * while the run keeps growing, so one episode shows one offer.
     */
    val episodeKey: String,
    val currentTargetMinutes: Int,
    val suggestedTargetMinutes: Int,
)

/**
 * Pure derivation — no per-day target history exists, so every judged day is
 * compared against the *current* effective target. That skew is benign:
 * accepting the offer lowers the target and thereby ends the episode.
 *
 * "Missed" mirrors the Daily Unlock ladder ([UnlockPolicy.grant]): the
 * unlock needs a single session at or past the target, so a day is missed
 * when no single session reached it. Days are local — the gate's own
 * semantics — never UTC.
 */
object AdaptiveTargetPolicy {
    /** Roughly half, floor one minute. */
    fun suggestedMinutes(halving: Int): Int =
        (halving / 2.0).roundToInt().coerceAtLeast(1)

    fun evaluate(
        sessions: List<SessionSummary>,
        currentTargetMinutes: Int,
        firstOpenDate: Instant,
        now: Instant = Instant.now(),
        zoneId: ZoneId = ZoneId.systemDefault(),
    ): AdaptiveTargetOffer? {
        // Nothing to soften for someone who never wrote, and 1 minute has
        // no lower place to walk to.
        if (currentTargetMinutes <= 1 || sessions.isEmpty()) return null

        val targetMs = currentTargetMinutes * 60_000L
        val bestSessionMsByDay = sessions
            .groupBy { it.createdAt.atZone(zoneId).toLocalDate() }
            .mapValues { (_, daySessions) -> daySessions.maxOf { it.durationMs } }

        // Judge only completed days, and none from before the app existed.
        val firstJudgedDay = firstOpenDate.atZone(zoneId).toLocalDate()
        var day = now.atZone(zoneId).toLocalDate().minusDays(1)

        var runStart: LocalDate? = null
        var runLength = 0
        while (day >= firstJudgedDay) {
            if ((bestSessionMsByDay[day] ?: 0L) >= targetMs) break
            runStart = day
            runLength += 1
            day = day.minusDays(1)
        }

        val start = runStart
        if (runLength < 2 || start == null) return null
        return AdaptiveTargetOffer(
            episodeKey = isoDay(start),
            currentTargetMinutes = currentTargetMinutes,
            suggestedTargetMinutes = suggestedMinutes(halving = currentTargetMinutes),
        )
    }

    fun isoDay(day: LocalDate): String =
        String.format(Locale.US, "%04d-%02d-%02d", day.year, day.monthValue, day.dayOfMonth)
}

/** Remembers which episode already had its one offer. */
class AdaptiveTargetOfferStore(
    private val preferences: SharedPreferences,
) {
    fun hasShown(episodeKey: String): Boolean =
        preferences.getString(Key, null) == episodeKey

    fun markShown(episodeKey: String) {
        preferences.edit().putString(Key, episodeKey).apply()
    }

    companion object {
        const val Key = "writeBeforeScroll.adaptiveOffer.v1"
    }
}
