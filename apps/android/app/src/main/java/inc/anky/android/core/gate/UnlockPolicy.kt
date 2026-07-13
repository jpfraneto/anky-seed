package inc.anky.android.core.gate

import android.content.SharedPreferences
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * The two ways through the gate:
 * - [Quick]: one completed sentence opens a 15-minute Quick Pass.
 *   Anky grants three per day.
 * - [Daily]: writing to the personal daily target opens the rest of the day.
 */
enum class UnlockTier(val rawValue: String) {
    Quick("quick_pass"),
    Daily("daily_unlock"),
    ;

    val displayName: String
        get() = when (this) {
            Quick -> "quick pass"
            Daily -> "daily unlock"
        }

    val unlockRank: Int
        get() = when (this) {
            Quick -> 0
            Daily -> 1
        }

    companion object {
        fun fromRawValue(rawValue: String?): UnlockTier? =
            entries.firstOrNull { it.rawValue == rawValue }
    }
}

data class UnlockGrant(
    val tier: UnlockTier,
    val unlockedUntil: Instant,
    val grantedAt: Instant,
)

/**
 * The slice of the writing surface the gate engine judges. The writing
 * workstream maps its session engine state into this (iOS:
 * `WritingSessionSnapshot` in WritingSessionEngine.swift).
 */
data class GateWritingSnapshot(
    val reconstructedText: String,
    val elapsedMs: Long,
) {
    val hasCompletedSentence: Boolean
        get() = UnlockPolicy.hasCompletedQuickSentence(reconstructedText)

    val hasUnlockableWriting: Boolean
        get() = reconstructedText.any { !it.isWhitespace() }
}

class UnlockPolicy(
    private val zoneId: ZoneId = ZoneId.systemDefault(),
) {
    /**
     * The daily target is a floor, never a ceiling: reaching it earns the
     * daily unlock while writing continues untouched.
     *
     * Phase 3: the Daily Unlock is part of the subscription
     * ([dailyUnlockEntitled]). Quick Passes and the emergency breath belong
     * to everyone forever — protection is never revoked for non-payment,
     * and a free writer at their target still earns a Quick Pass.
     */
    fun grant(
        snapshot: GateWritingSnapshot,
        at: Instant = Instant.now(),
        dailyTargetMs: Long = DefaultDailyTargetMs,
        quickPassesRemaining: Int = QuickPassDailyAllowance,
        dailyUnlockEntitled: Boolean = true,
    ): UnlockGrant? {
        if (dailyUnlockEntitled && snapshot.elapsedMs >= dailyTargetMs) {
            return UnlockGrant(
                tier = UnlockTier.Daily,
                unlockedUntil = endOfLocalDay(containing = at),
                grantedAt = at,
            )
        }

        if (snapshot.hasCompletedSentence && quickPassesRemaining > 0) {
            return UnlockGrant(
                tier = UnlockTier.Quick,
                unlockedUntil = at.plusSeconds(QuickPassUnlockSeconds),
                grantedAt = at,
            )
        }

        return null
    }

    private fun endOfLocalDay(containing: Instant): Instant =
        containing.atZone(zoneId).toLocalDate().plusDays(1).atStartOfDay(zoneId).toInstant()

    companion object {
        const val QuickPassUnlockSeconds: Long = 15 * 60
        const val QuickPassDailyAllowance = 3
        const val DefaultDailyTargetMinutes = 8
        const val DefaultDailyTargetMs: Long = DefaultDailyTargetMinutes * 60_000L

        /**
         * Quick Pass completes at ~5-7 words OR terminal punctuation, whichever
         * comes first. No judgment of content — the 3/day cap is the limiter.
         */
        const val QuickPassWordThreshold = 6

        /**
         * The Quick Pass trigger: a completed sentence OR enough words that a
         * sentence is clearly underway. Fires the moment either lands.
         */
        fun hasCompletedQuickSentence(text: String): Boolean =
            hasCompletedSentence(text) || wordCount(text) >= QuickPassWordThreshold

        fun wordCount(text: String): Int =
            text.split { it.isWhitespace() }.size

        /**
         * A completed sentence is a `.`, `!`, or `?` whose nearest preceding
         * non-whitespace character is a letter or number — so `hello`, `...`,
         * `!?`, and `     .` never unlock, while `I am here.` and `Enough!` do.
         */
        fun hasCompletedSentence(text: String): Boolean {
            var lastMeaningfulCharacter: Char? = null
            for (character in text) {
                val previous = lastMeaningfulCharacter
                if ((character == '.' || character == '!' || character == '?') &&
                    previous != null &&
                    (previous.isLetter() || previous.isDigit())
                ) {
                    return true
                }
                if (!character.isWhitespace()) {
                    lastMeaningfulCharacter = character
                }
            }
            return false
        }

        /** Mirror of Swift's `split(whereSeparator:)` — empty pieces never count. */
        private fun String.split(predicate: (Char) -> Boolean): List<String> {
            val pieces = mutableListOf<String>()
            val current = StringBuilder()
            for (character in this) {
                if (predicate(character)) {
                    if (current.isNotEmpty()) {
                        pieces.add(current.toString())
                        current.setLength(0)
                    }
                } else {
                    current.append(character)
                }
            }
            if (current.isNotEmpty()) pieces.add(current.toString())
            return pieces
        }
    }
}

/**
 * What the writing surface does with the grant computed on an accepted
 * keystroke.
 */
sealed class WriteBeforeScrollUnlockLadderAction {
    /** Hold the grant for the sealing screen's gate button. */
    data class Offer(val grant: UnlockGrant) : WriteBeforeScrollUnlockLadderAction()

    /**
     * §5.4: the Quick Pass applies by itself the moment the sentence
     * completes — no button, no stillness.
     */
    data class ApplyQuickPassively(val grant: UnlockGrant) : WriteBeforeScrollUnlockLadderAction()

    /**
     * Crossing the daily target while a Quick Pass window is open replaces
     * the 15-minute window with the rest of the day, on the spot.
     */
    data class UpgradeToDaily(val grant: UnlockGrant) : WriteBeforeScrollUnlockLadderAction()

    /**
     * A free (or lapsed) writer crossed their daily target: hold the
     * moment screen for the sealing flow — never a silent nothing
     * (decision 2026-07-06, option C). At most once per day.
     */
    data object OfferFreeTargetMoment : WriteBeforeScrollUnlockLadderAction()

    /** Nothing to hold — clear any previously offered grant. */
    data object Withdraw : WriteBeforeScrollUnlockLadderAction()
}

/**
 * Resolves the unlock ladder for one accepted keystroke.
 *
 * Three rules beyond [UnlockPolicy.grant]:
 * - Quick Passes belong to the gate. An organic session never surfaces or
 *   spends one — it still counts toward the daily target and level progress.
 * - The Daily Unlock is never discarded because a Quick Pass already opened
 *   the shield: while the pass window is active it upgrades in place, and
 *   otherwise it is offered as usual.
 * - A free writer's target crossing is acknowledged with the moment screen
 *   (once per day) instead of resolving to nothing.
 */
class WriteBeforeScrollUnlockLadder {
    fun action(
        grant: UnlockGrant?,
        unlockState: UnlockState,
        isGateOriginatedSession: Boolean,
        hasAppliedPassiveQuickUnlock: Boolean,
        hasAppliedDailyUnlockUpgrade: Boolean,
        dailyUnlockEntitled: Boolean = true,
        hasReachedDailyTarget: Boolean = false,
        hasOfferedFreeTargetMoment: Boolean = true,
        at: Instant = Instant.now(),
    ): WriteBeforeScrollUnlockLadderAction {
        if (!dailyUnlockEntitled && hasReachedDailyTarget && !hasOfferedFreeTargetMoment) {
            return WriteBeforeScrollUnlockLadderAction.OfferFreeTargetMoment
        }
        if (grant == null) {
            return WriteBeforeScrollUnlockLadderAction.Withdraw
        }
        val isUnlocked = unlockState.isUnlocked(at)
        return when (grant.tier) {
            UnlockTier.Quick -> {
                if (!isGateOriginatedSession || isUnlocked) {
                    WriteBeforeScrollUnlockLadderAction.Withdraw
                } else if (hasAppliedPassiveQuickUnlock) {
                    WriteBeforeScrollUnlockLadderAction.Offer(grant)
                } else {
                    WriteBeforeScrollUnlockLadderAction.ApplyQuickPassively(grant)
                }
            }
            UnlockTier.Daily -> {
                if (isUnlocked &&
                    unlockState.grant?.tier == UnlockTier.Quick &&
                    !hasAppliedDailyUnlockUpgrade
                ) {
                    WriteBeforeScrollUnlockLadderAction.UpgradeToDaily(grant)
                } else {
                    WriteBeforeScrollUnlockLadderAction.Offer(grant)
                }
            }
        }
    }
}

/**
 * Once-per-local-day ledger for the free-tier target moment: however many
 * sessions cross the target, the moment screen shows at most once a day.
 * Main-app presentation state only.
 */
class FreeTargetMomentLedger(
    private val preferences: SharedPreferences,
    private val zoneId: ZoneId = ZoneId.systemDefault(),
) {
    fun wasShown(on: Instant = Instant.now()): Boolean {
        if (!preferences.contains(Key)) return false
        val lastShown = Instant.ofEpochMilli(preferences.getLong(Key, 0L))
        return localDay(lastShown) == localDay(on)
    }

    fun markShown(on: Instant = Instant.now()) {
        preferences.edit().putLong(Key, on.toEpochMilli()).apply()
    }

    private fun localDay(instant: Instant): LocalDate = instant.atZone(zoneId).toLocalDate()

    private companion object {
        const val Key = "anky.freeTargetMoment.lastShownDay"
    }
}
