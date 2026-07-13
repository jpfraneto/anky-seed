package inc.anky.android.core.gate

import android.content.SharedPreferences
import java.time.Instant
import java.time.ZoneId
import org.json.JSONObject

/**
 * The writer's personal daily target (1–8 minutes, default 8) — the floor
 * that earns the Daily Unlock. Sessions are never cut off at the target.
 *
 * It contains no writing — only minutes and dates.
 *
 * Edit semantics: the initial onboarding choice applies immediately; later
 * edits take effect the next local day, so the current day's gate cannot be
 * lowered mid-lock.
 */
data class DailyTargetState(
    val targetMinutes: Int,
    val pendingTargetMinutes: Int? = null,
    val pendingRequestedAt: Instant? = null,
)

data class DailyTargetChange(
    val oldMinutes: Int,
    val newMinutes: Int,
)

class DailyTargetStore(
    private val preferences: SharedPreferences,
) {
    /**
     * The target in force right now, promoting any pending change whose
     * request day has passed.
     */
    fun effectiveTargetMinutes(now: Instant = Instant.now(), zoneId: ZoneId = ZoneId.systemDefault()): Int {
        var state = load()
        val pendingMinutes = state.pendingTargetMinutes
        val requestedAt = state.pendingRequestedAt
        if (pendingMinutes != null &&
            requestedAt != null &&
            requestedAt.atZone(zoneId).toLocalDate() != now.atZone(zoneId).toLocalDate() &&
            requestedAt.isBefore(now)
        ) {
            state = DailyTargetState(
                targetMinutes = pendingMinutes,
                pendingTargetMinutes = null,
                pendingRequestedAt = null,
            )
            save(state)
        }
        return clamp(state.targetMinutes)
    }

    fun effectiveTargetMs(now: Instant = Instant.now(), zoneId: ZoneId = ZoneId.systemDefault()): Long =
        effectiveTargetMinutes(now, zoneId) * 60_000L

    /** The pending next-day value, if an edit is waiting to take effect. */
    fun pendingTargetMinutes(now: Instant = Instant.now(), zoneId: ZoneId = ZoneId.systemDefault()): Int? {
        effectiveTargetMinutes(now, zoneId)
        return load().pendingTargetMinutes
    }

    /**
     * Adaptive offer (phase-2 §1): an accepted lower target takes effect
     * immediately — the writer said yes to relief, not to paperwork.
     */
    fun applyImmediateTarget(minutes: Int) {
        setInitialTarget(minutes)
    }

    /** Onboarding: the first choice applies immediately. */
    fun setInitialTarget(minutes: Int) {
        save(
            DailyTargetState(
                targetMinutes = clamp(minutes),
                pendingTargetMinutes = null,
                pendingRequestedAt = null,
            ),
        )
    }

    /**
     * Later edits apply from the next local day. Returns (old, new) for
     * event logging. Requesting the currently-active value cancels any
     * pending change.
     */
    fun requestTargetChange(
        minutes: Int,
        now: Instant = Instant.now(),
        zoneId: ZoneId = ZoneId.systemDefault(),
    ): DailyTargetChange {
        val current = effectiveTargetMinutes(now, zoneId)
        val requested = clamp(minutes)
        val state = load()

        save(
            if (requested == current) {
                state.copy(pendingTargetMinutes = null, pendingRequestedAt = null)
            } else {
                state.copy(pendingTargetMinutes = requested, pendingRequestedAt = now)
            },
        )
        return DailyTargetChange(oldMinutes = current, newMinutes = requested)
    }

    private fun load(): DailyTargetState {
        val raw = preferences.getString(Key, null)
            ?: return DailyTargetState(targetMinutes = DefaultMinutes)
        return runCatching {
            val json = JSONObject(raw)
            DailyTargetState(
                targetMinutes = json.getInt("targetMinutes"),
                pendingTargetMinutes = if (json.has("pendingTargetMinutes")) {
                    json.getInt("pendingTargetMinutes")
                } else {
                    null
                },
                pendingRequestedAt = json.optString("pendingRequestedAt", "")
                    .takeIf { it.isNotEmpty() }
                    ?.let(Instant::parse),
            )
        }.getOrDefault(DailyTargetState(targetMinutes = DefaultMinutes))
    }

    private fun save(state: DailyTargetState) {
        val json = JSONObject().put("targetMinutes", state.targetMinutes)
        state.pendingTargetMinutes?.let { json.put("pendingTargetMinutes", it) }
        state.pendingRequestedAt?.let { json.put("pendingRequestedAt", it.toString()) }
        preferences.edit().putString(Key, json.toString()).apply()
    }

    private fun clamp(minutes: Int): Int = minutes.coerceIn(MinutesRange)

    companion object {
        const val Key = "writeBeforeScroll.dailyTarget.v1"
        val MinutesRange = 1..8
        const val DefaultMinutes = UnlockPolicy.DefaultDailyTargetMinutes
    }
}
