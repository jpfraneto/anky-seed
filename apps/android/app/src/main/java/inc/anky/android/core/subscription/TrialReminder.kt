package inc.anky.android.core.subscription

/**
 * The honest trial reminder as PURE LOGIC. The actual AlarmManager +
 * NotificationManager implementation of [TrialReminderPort] lands in the
 * notifications workstream (it needs manifest entries: SCHEDULE_EXACT_ALARM /
 * POST_NOTIFICATIONS and a receiver); this package only decides WHEN.
 *
 * Ported from iOS `LocalNotificationScheduler.swift` (trial parts) +
 * `EntitlementStore.syncTrialReminder` / `reconcileOnForeground`.
 */
object TrialReminderContract {
    /** Stable identifier for the pending reminder (notification tag / work name). */
    const val REMINDER_ID = "anky.trial-ending-reminder"

    /** Copy, verbatim from iOS with the store name made honest for Android. */
    const val TITLE = "Your trial ends tomorrow"
    const val BODY =
        "If Anky isn't yours, cancel in Google Play subscriptions and part as friends. " +
            "If it is — day 3 is the first Daily Unlock."
}

/** What the planner decided for the current entitlement truth. */
sealed interface TrialReminderAction {
    /** Place (or move) the reminder; scheduling replaces any pending one. */
    data class Schedule(val fireAtEpochMillis: Long) : TrialReminderAction

    /** No trial (cancelled, converted, lapsed, or never started): remove it. */
    data object Cancel : TrialReminderAction

    /** Inside the lead window already — leave whatever is pending untouched. */
    data object None : TrialReminderAction
}

/**
 * Places the trial-ending reminder 28 hours before the trial converts, from
 * the entitlement's own expiration date — no local timestamp heuristics.
 * Re-run on every customer-info change: a cancelled or converted trial
 * removes the reminder, a fresher end date moves it. Run again after
 * notification permission is granted, since the paywall comes one screen
 * before the ask; and on every foreground, so a trial cancelled in Play
 * settings loses its reminder (iOS `reconcileOnForeground`).
 */
object TrialReminderPlanner {
    fun plan(snapshot: EntitlementSnapshot, nowMillis: Long): TrialReminderAction {
        val expiration = snapshot.expirationDateMillis
        if (!snapshot.isInIntroTrial || expiration == null) {
            return TrialReminderAction.Cancel
        }
        val fireAt = expiration - AnkyPurchasesConfig.TRIAL_REMINDER_LEAD_TIME_MILLIS
        if (fireAt <= nowMillis) {
            return TrialReminderAction.None
        }
        return TrialReminderAction.Schedule(fireAt)
    }
}

/**
 * The seam to the platform scheduler. Implemented later with AlarmManager (or
 * WorkManager) + a notification using [TrialReminderContract]; faked in tests.
 */
interface TrialReminderPort {
    /** Schedules the reminder, replacing any previously pending one. */
    suspend fun scheduleTrialEndingReminder(fireAtEpochMillis: Long)

    fun cancelTrialEndingReminder()
}

/** Applies [TrialReminderPlanner] decisions to a [TrialReminderPort]. */
class TrialReminderSync(
    private val port: TrialReminderPort,
    private val nowMillis: () -> Long = System::currentTimeMillis,
) {
    suspend fun sync(snapshot: EntitlementSnapshot) {
        when (val action = TrialReminderPlanner.plan(snapshot, nowMillis())) {
            is TrialReminderAction.Schedule ->
                runCatching { port.scheduleTrialEndingReminder(action.fireAtEpochMillis) }
            TrialReminderAction.Cancel -> port.cancelTrialEndingReminder()
            TrialReminderAction.None -> Unit
        }
    }
}
