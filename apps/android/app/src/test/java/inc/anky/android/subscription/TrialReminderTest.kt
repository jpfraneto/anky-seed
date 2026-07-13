package inc.anky.android.subscription

import inc.anky.android.core.subscription.AnkyPurchasesConfig
import inc.anky.android.core.subscription.EntitlementSnapshot
import inc.anky.android.core.subscription.SubscriptionPeriodKind
import inc.anky.android.core.subscription.SubscriptionStoreKind
import inc.anky.android.core.subscription.TrialReminderAction
import inc.anky.android.core.subscription.TrialReminderPlanner
import inc.anky.android.core.subscription.TrialReminderSync
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TrialReminderTest {
    private val now = 1_750_000_000_000L
    private val hour = 60L * 60L * 1000L

    private fun trialSnapshot(
        expiresInMillis: Long?,
        periodType: SubscriptionPeriodKind = SubscriptionPeriodKind.TRIAL,
        entitled: Boolean = true,
    ) = EntitlementSnapshot(
        isEntitled = entitled,
        productId = "anky.yearly",
        store = SubscriptionStoreKind.PLAY_STORE,
        periodType = periodType,
        expirationDateMillis = expiresInMillis?.let { now + it },
    )

    @Test
    fun leadTimeIsTwentyEightHours() {
        assertEquals(28L * hour, AnkyPurchasesConfig.TRIAL_REMINDER_LEAD_TIME_MILLIS)
    }

    @Test
    fun trialSchedulesTwentyEightHoursBeforeConversion() {
        // A fresh 72h trial: the reminder lands at the old 44h-in mark.
        val action = TrialReminderPlanner.plan(trialSnapshot(expiresInMillis = 72L * hour), now)

        assertEquals(TrialReminderAction.Schedule(now + 44L * hour), action)
    }

    @Test
    fun paidIntroPeriodGetsTheSameHonesty() {
        val action = TrialReminderPlanner.plan(
            trialSnapshot(expiresInMillis = 72L * hour, periodType = SubscriptionPeriodKind.INTRO),
            now,
        )

        assertTrue(action is TrialReminderAction.Schedule)
    }

    @Test
    fun normalSubscriptionCancelsTheReminder() {
        // A converted trial is a NORMAL period — the reminder must go.
        val action = TrialReminderPlanner.plan(
            trialSnapshot(expiresInMillis = 300L * hour, periodType = SubscriptionPeriodKind.NORMAL),
            now,
        )

        assertEquals(TrialReminderAction.Cancel, action)
    }

    @Test
    fun lapsedEntitlementCancelsTheReminder() {
        // Trial cancelled in Play settings, entitlement gone on foreground.
        val action = TrialReminderPlanner.plan(EntitlementSnapshot.NOT_ENTITLED, now)

        assertEquals(TrialReminderAction.Cancel, action)
    }

    @Test
    fun missingExpirationCancelsTheReminder() {
        val action = TrialReminderPlanner.plan(trialSnapshot(expiresInMillis = null), now)

        assertEquals(TrialReminderAction.Cancel, action)
    }

    @Test
    fun insideTheLeadWindowLeavesPendingStateUntouched() {
        // 10h left on the trial: the fire time is in the past — do nothing,
        // exactly like iOS (no schedule, no cancel).
        val action = TrialReminderPlanner.plan(trialSnapshot(expiresInMillis = 10L * hour), now)

        assertEquals(TrialReminderAction.None, action)
    }

    @Test
    fun syncAppliesPlanToThePort() = runTest {
        val port = RecordingTrialReminderPort()
        val sync = TrialReminderSync(port, nowMillis = { now })

        sync.sync(trialSnapshot(expiresInMillis = 72L * hour))
        assertEquals(listOf(now + 44L * hour), port.scheduledAt)
        assertEquals(0, port.cancelCount)

        sync.sync(EntitlementSnapshot.NOT_ENTITLED)
        assertEquals(1, port.cancelCount)

        sync.sync(trialSnapshot(expiresInMillis = 10L * hour))
        assertEquals(1, port.scheduledAt.size)
        assertEquals(1, port.cancelCount)
    }
}
