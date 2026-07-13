package inc.anky.android.core.gate

import android.content.SharedPreferences
import java.time.Instant
import java.time.ZoneId
import org.json.JSONObject

/**
 * Quick Passes: Anky grants three 15-minute passes a day, resetting at
 * local midnight. The framing is generosity — passes are granted, never
 * lost — and running out simply means the door opens through writing to
 * the daily target instead.
 *
 * Contains only a day marker and a count.
 */
data class QuickPassState(
    val dayStart: Instant,
    val usedCount: Int,
)

class QuickPassStore(
    private val preferences: SharedPreferences,
) {
    fun remainingPasses(now: Instant = Instant.now(), zoneId: ZoneId = ZoneId.systemDefault()): Int =
        (DailyAllowance - currentState(now, zoneId).usedCount).coerceAtLeast(0)

    /**
     * Consumes one pass and returns its number today (1, 2, or 3), or null
     * when the day's passes are already spent.
     */
    fun consumePass(now: Instant = Instant.now(), zoneId: ZoneId = ZoneId.systemDefault()): Int? {
        val state = currentState(now, zoneId)
        if (state.usedCount >= DailyAllowance) {
            return null
        }
        val next = state.copy(usedCount = state.usedCount + 1)
        save(next)
        return next.usedCount
    }

    private fun currentState(now: Instant, zoneId: ZoneId): QuickPassState {
        val today = now.atZone(zoneId).toLocalDate()
        val fresh = QuickPassState(dayStart = today.atStartOfDay(zoneId).toInstant(), usedCount = 0)
        val raw = preferences.getString(Key, null) ?: return fresh
        return runCatching {
            val json = JSONObject(raw)
            val state = QuickPassState(
                dayStart = Instant.parse(json.getString("dayStart")),
                usedCount = json.getInt("usedCount"),
            )
            if (state.dayStart.atZone(zoneId).toLocalDate() == today) state else fresh
        }.getOrDefault(fresh)
    }

    private fun save(state: QuickPassState) {
        val json = JSONObject()
            .put("dayStart", state.dayStart.toString())
            .put("usedCount", state.usedCount)
        preferences.edit().putString(Key, json.toString()).apply()
    }

    companion object {
        const val Key = "writeBeforeScroll.quickPasses.v1"

        // Literal (not UnlockPolicy.QuickPassDailyAllowance) to mirror the iOS
        // store, which also compiles into shield extensions.
        const val DailyAllowance = 3
    }
}
