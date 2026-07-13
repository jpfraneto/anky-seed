package inc.anky.android.core.gate

import android.content.SharedPreferences
import java.time.Instant
import org.json.JSONArray
import org.json.JSONObject

/**
 * Persisted, local-only progress through the 8-Day Gate. Stores only day
 * numbers and completion dates — never writing, never the anchor. Missed
 * days are not punished: completions are permanent and the current day
 * simply waits for the writer to return.
 */
data class EightDayGateProgress(
    val completions: List<DayCompletion> = emptyList(),
) {
    data class DayCompletion(
        val dayNumber: Int,
        val completedAt: Instant,
    )

    fun isDayComplete(dayNumber: Int): Boolean =
        completions.any { it.dayNumber == dayNumber }

    fun completionDate(dayNumber: Int): Instant? =
        completions.firstOrNull { it.dayNumber == dayNumber }?.completedAt

    val isComplete: Boolean
        get() = (1..8).all(::isDayComplete)

    /**
     * The first incomplete day — the day the writer is on. Day 8 once
     * everything is done.
     */
    val currentDayNumber: Int
        get() = (1..8).firstOrNull { !isDayComplete(it) } ?: 8

    val completedDayCount: Int
        get() = (1..8).count(::isDayComplete)

    /** Idempotent: the first completion date for a day is kept forever. */
    fun markCompleted(dayNumber: Int, at: Instant = Instant.now()): EightDayGateProgress {
        if (dayNumber !in 1..8 || isDayComplete(dayNumber)) {
            return this
        }
        return copy(completions = completions + DayCompletion(dayNumber, at))
    }
}

class EightDayGateStore(
    private val preferences: SharedPreferences,
) {
    fun load(): EightDayGateProgress {
        val raw = preferences.getString(Key, null) ?: return EightDayGateProgress()
        return runCatching {
            val array = JSONArray(raw)
            EightDayGateProgress(
                completions = (0 until array.length()).map { index ->
                    val json = array.getJSONObject(index)
                    EightDayGateProgress.DayCompletion(
                        dayNumber = json.getInt("dayNumber"),
                        completedAt = Instant.parse(json.getString("completedAt")),
                    )
                },
            )
        }.getOrDefault(EightDayGateProgress())
    }

    fun save(progress: EightDayGateProgress) {
        val array = JSONArray()
        progress.completions.forEach { completion ->
            array.put(
                JSONObject()
                    .put("dayNumber", completion.dayNumber)
                    .put("completedAt", completion.completedAt.toString()),
            )
        }
        preferences.edit().putString(Key, array.toString()).apply()
    }

    fun markCompleted(dayNumber: Int, at: Instant = Instant.now()) {
        save(load().markCompleted(dayNumber, at))
    }

    /**
     * Marks every day that can be honestly derived from local state, then
     * persists and returns the result. Days that cannot be derived yet:
     * - Day 4 (read an archive echo) is marked event-driven when the user
     *   opens an archive reveal.
     * - Day 5 (protect your morning) is scaffolded: no morning schedule
     *   feature exists yet, so it is never auto-marked.
     * - Day 6 (share) is scaffolded: share cards are not implemented yet.
     */
    fun refreshDerivedCompletions(
        hasCompletedFirstGate: Boolean,
        protectedTargetCount: Int,
        hasCompletedDailyUnlock: Boolean,
        hasWrittenPastTarget: Boolean,
        isGateOn: Boolean,
        now: Instant = Instant.now(),
    ): EightDayGateProgress {
        var progress = load()

        if (hasCompletedFirstGate) {
            progress = progress.markCompleted(1, now)
        }
        if (protectedTargetCount >= 2) {
            progress = progress.markCompleted(2, now)
        }
        if (hasCompletedDailyUnlock) {
            progress = progress.markCompleted(3, now)
        }
        if (hasWrittenPastTarget) {
            progress = progress.markCompleted(7, now)
        }
        if ((1..7).all(progress::isDayComplete) && isGateOn) {
            progress = progress.markCompleted(8, now)
        }

        save(progress)
        return progress
    }

    companion object {
        const val Key = "anky.wbs.eightDayGateProgress.v1"
    }
}
