package inc.anky.android.core.storage

import android.content.Context
import java.time.Instant
import java.time.ZoneId

class AppOpenStore(
    context: Context,
) {
    private val preferences = context.applicationContext.getSharedPreferences("anky-app-open", Context.MODE_PRIVATE)

    fun loadOrCreate(now: Instant = Instant.now()): Instant {
        val stored = preferences.getLong(KEY_FIRST_OPEN_EPOCH_MS, -1L)
        if (stored >= 0L) return Instant.ofEpochMilli(stored)
        preferences.edit().putLong(KEY_FIRST_OPEN_EPOCH_MS, now.toEpochMilli()).apply()
        return now
    }

    fun recordEarlierFirstOpenDate(candidate: Instant, zoneId: ZoneId = ZoneId.systemDefault()): Instant {
        val candidateDay = candidate.startOfLocalDay(zoneId)
        val stored = preferences.getLong(KEY_FIRST_OPEN_EPOCH_MS, -1L)
        if (stored < 0L) {
            preferences.edit().putLong(KEY_FIRST_OPEN_EPOCH_MS, candidateDay.toEpochMilli()).apply()
            return candidateDay
        }

        val current = Instant.ofEpochMilli(stored)
        val currentDay = current.startOfLocalDay(zoneId)
        if (!candidateDay.isBefore(currentDay)) return current
        preferences.edit().putLong(KEY_FIRST_OPEN_EPOCH_MS, candidateDay.toEpochMilli()).apply()
        return candidateDay
    }

    fun clear() {
        preferences.edit().remove(KEY_FIRST_OPEN_EPOCH_MS).apply()
    }

    private companion object {
        const val KEY_FIRST_OPEN_EPOCH_MS = "first_open_epoch_ms"
    }
}

internal fun Instant.startOfLocalDay(zoneId: ZoneId): Instant =
    atZone(zoneId).toLocalDate().atStartOfDay(zoneId).toInstant()
