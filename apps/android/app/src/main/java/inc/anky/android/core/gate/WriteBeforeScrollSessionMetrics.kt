package inc.anky.android.core.gate

import java.time.Duration
import java.time.Instant
import java.util.UUID

data class WriteBeforeScrollSessionMetrics(
    val sessionId: UUID = UUID.randomUUID(),
    val firstUnlockTierRawValue: String? = null,
    val unlockAvailableAt: Instant? = null,
    val continuedWritingAfterUnlockAvailable: Boolean = false,
    val charactersAfterUnlockAvailable: Int = 0,
    val secondsWritingAfterUnlockAvailable: Double = 0.0,
    val finalTierRawValue: String? = null,
    val totalAcceptedCharacters: Int = 0,
    val elapsedMs: Long = 0,
    val hasQuickPassAvailable: Boolean = false,
    val hasDailyUnlockAvailable: Boolean = false,
) {
    val firstUnlockTier: UnlockTier?
        get() = UnlockTier.fromRawValue(firstUnlockTierRawValue)

    val finalTier: UnlockTier?
        get() = UnlockTier.fromRawValue(finalTierRawValue)

    val currentThresholdStateText: String
        get() = listOf(
            "quick pass: ${if (hasQuickPassAvailable) "yes" else "no"}",
            "daily unlock: ${if (hasDailyUnlockAvailable) "yes" else "no"}",
        ).joinToString(separator = ", ")

    val goldenMetricText: String
        get() {
            if (firstUnlockTier == null) {
                return "no unlock available yet"
            }
            return if (continuedWritingAfterUnlockAvailable) {
                "true, $charactersAfterUnlockAvailable chars, ${secondsWritingAfterUnlockAvailable.toInt()}s"
            } else {
                "false"
            }
        }
}

data class WriteBeforeScrollSessionMetricUpdate(
    val metrics: WriteBeforeScrollSessionMetrics,
    val availableGrant: UnlockGrant?,
    val events: List<WriteBeforeScrollEventName>,
)

class WriteBeforeScrollSessionMetricTracker(
    metrics: WriteBeforeScrollSessionMetrics = WriteBeforeScrollSessionMetrics(),
) {
    var metrics: WriteBeforeScrollSessionMetrics = metrics
        private set

    private var hasLoggedWritingStarted = false
    private var loggedAvailableTiers = mutableSetOf<UnlockTier>()
    private var hasLoggedContinuedWriting = false

    fun recordAcceptedCharacters(
        count: Int,
        snapshot: GateWritingSnapshot,
        at: Instant,
        policy: UnlockPolicy = UnlockPolicy(),
        dailyTargetMs: Long = UnlockPolicy.DefaultDailyTargetMs,
        quickPassesRemaining: Int = UnlockPolicy.QuickPassDailyAllowance,
        dailyUnlockEntitled: Boolean = true,
    ): WriteBeforeScrollSessionMetricUpdate {
        if (count <= 0) {
            return WriteBeforeScrollSessionMetricUpdate(metrics = metrics, availableGrant = null, events = emptyList())
        }

        val events = mutableListOf<WriteBeforeScrollEventName>()
        if (!hasLoggedWritingStarted) {
            hasLoggedWritingStarted = true
            events.add(WriteBeforeScrollEventName.WritingStarted)
        }

        metrics = metrics.copy(
            totalAcceptedCharacters = metrics.totalAcceptedCharacters + count,
            elapsedMs = snapshot.elapsedMs,
        )

        val unlockAvailableAt = metrics.unlockAvailableAt
        if (unlockAvailableAt != null) {
            metrics = metrics.copy(
                charactersAfterUnlockAvailable = metrics.charactersAfterUnlockAvailable + count,
                secondsWritingAfterUnlockAvailable = maxOf(
                    metrics.secondsWritingAfterUnlockAvailable,
                    Duration.between(unlockAvailableAt, at).toMillis() / 1_000.0,
                ),
            )
            if (!hasLoggedContinuedWriting) {
                metrics = metrics.copy(continuedWritingAfterUnlockAvailable = true)
                hasLoggedContinuedWriting = true
                events.add(WriteBeforeScrollEventName.ContinuedWritingAfterUnlockAvailable)
            }
        }

        val availableTiers = availableTiers(
            snapshot = snapshot,
            dailyTargetMs = dailyTargetMs,
            quickPassesRemaining = quickPassesRemaining,
            dailyUnlockEntitled = dailyUnlockEntitled,
        )
        metrics = metrics.copy(
            hasQuickPassAvailable = UnlockTier.Quick in availableTiers,
            hasDailyUnlockAvailable = UnlockTier.Daily in availableTiers,
        )

        var newlyAvailableGrant: UnlockGrant? = null
        for (tier in availableTiers.sortedBy { it.unlockRank }) {
            if (tier in loggedAvailableTiers) {
                continue
            }
            loggedAvailableTiers.add(tier)
            if (metrics.firstUnlockTierRawValue == null) {
                metrics = metrics.copy(
                    firstUnlockTierRawValue = tier.rawValue,
                    unlockAvailableAt = at,
                )
            }
            metrics = metrics.copy(finalTierRawValue = tier.rawValue)
            events.add(eventName(availableTier = tier))
            newlyAvailableGrant = policy.grant(
                snapshot = snapshot,
                at = at,
                dailyTargetMs = dailyTargetMs,
                quickPassesRemaining = quickPassesRemaining,
                dailyUnlockEntitled = dailyUnlockEntitled,
            )
        }

        return WriteBeforeScrollSessionMetricUpdate(
            metrics = metrics,
            availableGrant = newlyAvailableGrant,
            events = events,
        )
    }

    fun reset() {
        metrics = WriteBeforeScrollSessionMetrics()
        hasLoggedWritingStarted = false
        loggedAvailableTiers = mutableSetOf()
        hasLoggedContinuedWriting = false
    }

    private fun availableTiers(
        snapshot: GateWritingSnapshot,
        dailyTargetMs: Long,
        quickPassesRemaining: Int,
        dailyUnlockEntitled: Boolean,
    ): Set<UnlockTier> {
        val tiers = mutableSetOf<UnlockTier>()
        if (snapshot.hasCompletedSentence && quickPassesRemaining > 0) {
            tiers.add(UnlockTier.Quick)
        }
        // Phase-3: the Daily Unlock belongs to the subscription. The target
        // is still logged and the seconds still count — only the day-long
        // door needs the practice to be paid for.
        if (dailyUnlockEntitled && snapshot.elapsedMs >= dailyTargetMs) {
            tiers.add(UnlockTier.Daily)
        }
        return tiers
    }

    private fun eventName(availableTier: UnlockTier): WriteBeforeScrollEventName =
        when (availableTier) {
            UnlockTier.Quick -> WriteBeforeScrollEventName.SentenceUnlockAvailable
            UnlockTier.Daily -> WriteBeforeScrollEventName.DailyTargetReached
        }
}
