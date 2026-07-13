package inc.anky.android.core.gate

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * A local-only snapshot of the writer's protection and signal state,
 * derived from stores that already exist on device. Nothing here is sent
 * anywhere, and nothing here reads raw writing — only session dates,
 * unlock state, gate selection counts, and the WBS event log.
 */
data class SignalSnapshot(
    val isGateConfigured: Boolean,
    val isShieldActive: Boolean,
    val isCurrentlyUnlocked: Boolean,
    val unlockExpiresAt: Instant?,
    val unlockTier: UnlockTier?,
    val wroteToday: Boolean,
    val gatesCompletedToday: Int,
    val currentStreakDays: Int,
    val signalPercent: Int,
    val selectedApplicationCount: Int,
    val selectedCategoryCount: Int,
    val selectedWebDomainCount: Int,
)

object SignalCalculator {
    /**
     * Signal grows only with the writer's own return: 11% per consecutive
     * day of writing, plus 12% for having written today. Eight straight
     * days — the 8-Day Gate — reaches 100%. No penalties, no decay states:
     * a quiet day simply starts the count again.
     */
    fun signalPercent(streakDays: Int, wroteToday: Boolean): Int {
        val base = (streakDays.coerceAtLeast(0) * 11).coerceAtMost(88)
        return (base + if (wroteToday) 12 else 0).coerceAtMost(100)
    }

    /**
     * Consecutive days with at least one writing session, counting back
     * from today. A streak whose last writing day was yesterday still
     * counts — today is not lost until it is over.
     */
    fun streakDays(
        sessionDays: List<Instant>,
        now: Instant = Instant.now(),
        zoneId: ZoneId = ZoneId.systemDefault(),
    ): Int {
        val writingDays: Set<LocalDate> = sessionDays.map { it.atZone(zoneId).toLocalDate() }.toSet()
        if (writingDays.isEmpty()) {
            return 0
        }

        var cursor = now.atZone(zoneId).toLocalDate()
        if (cursor !in writingDays) {
            val yesterday = cursor.minusDays(1)
            if (yesterday !in writingDays) {
                return 0
            }
            cursor = yesterday
        }

        var streak = 0
        while (cursor in writingDays) {
            streak += 1
            cursor = cursor.minusDays(1)
        }
        return streak
    }

    fun snapshot(
        gateState: GateState,
        unlockState: UnlockState,
        events: List<WriteBeforeScrollEvent>,
        sessionDays: List<Instant>,
        now: Instant = Instant.now(),
        zoneId: ZoneId = ZoneId.systemDefault(),
    ): SignalSnapshot {
        val isUnlocked = gateState.isUnlocked(now) || unlockState.isUnlocked(now)
        val unlockExpiresAt = if (isUnlocked) {
            gateState.unlockedUntil ?: unlockState.grant?.unlockedUntil
        } else {
            null
        }
        val unlockTier = if (isUnlocked) {
            UnlockTier.fromRawValue(gateState.unlockTierRawValue) ?: unlockState.grant?.tier
        } else {
            null
        }

        val today = now.atZone(zoneId).toLocalDate()
        val wroteToday = unlockState.wroteToday(now, zoneId) ||
            sessionDays.any { it.atZone(zoneId).toLocalDate() == today }
        val gatesCompletedToday = events.count { event ->
            event.name == WriteBeforeScrollEventName.UnlockGranted &&
                event.timestamp.atZone(zoneId).toLocalDate() == today
        }

        val streak = streakDays(sessionDays, now, zoneId)

        return SignalSnapshot(
            isGateConfigured = gateState.hasSelection,
            isShieldActive = gateState.shieldActive,
            isCurrentlyUnlocked = isUnlocked,
            unlockExpiresAt = unlockExpiresAt,
            unlockTier = unlockTier,
            wroteToday = wroteToday,
            gatesCompletedToday = gatesCompletedToday,
            currentStreakDays = streak,
            signalPercent = signalPercent(streak, wroteToday),
            selectedApplicationCount = gateState.selectedApplicationCount,
            selectedCategoryCount = gateState.selectedCategoryCount,
            selectedWebDomainCount = gateState.selectedWebDomainCount,
        )
    }
}

/**
 * The first container: eight days of writing before the world gets in.
 * Progress is persisted locally by [EightDayGateStore]; this holds the
 * shared day definitions.
 */
object EightDayGate {
    val dayTitles = listOf(
        "Write before one app.",
        "Add your second noisy app.",
        "Complete your first Daily Unlock.",
        "Read your first archive echo.",
        "Protect your morning.",
        "Share that you wrote before scrolling.",
        "Write past your target.",
        "Choose your long-term gate.",
    )

    fun title(forDay: Int): String {
        val index = forDay.coerceIn(1, 8) - 1
        return dayTitles[index]
    }
}
