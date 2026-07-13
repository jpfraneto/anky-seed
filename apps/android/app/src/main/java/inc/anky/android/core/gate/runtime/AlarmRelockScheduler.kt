package inc.anky.android.core.gate.runtime

import android.annotation.SuppressLint
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import inc.anky.android.core.gate.GateStateStore
import inc.anky.android.core.gate.RelockSchedulerPort
import inc.anky.android.core.gate.WriteBeforeScrollEventLogStore
import inc.anky.android.core.gate.WriteBeforeScrollEventName
import java.time.Instant

/**
 * The relock-scheduling arithmetic, pure and JVM-testable. Mirrors the iOS
 * `WriteBeforeScrollUnlockScheduler` guard: windows shorter than five
 * seconds are refused (the watcher tick catches those anyway).
 */
object RelockPlanner {
    const val MinimumLeadSeconds = 5L

    sealed interface Plan {
        data class At(val triggerAtEpochMillis: Long) : Plan
        data object TooShort : Plan
    }

    fun plan(now: Instant, unlockedUntil: Instant): Plan =
        if (unlockedUntil.isAfter(now.plusSeconds(MinimumLeadSeconds))) {
            Plan.At(unlockedUntil.toEpochMilli())
        } else {
            Plan.TooShort
        }
}

/**
 * Where iOS schedules a DeviceActivity interval whose end relocks the
 * shield, Android arms an exact AlarmManager alarm at `unlockedUntil` that
 * fires [RelockReceiver]. Belt-and-braces: the [GateWatcherService] tick
 * reconciles too, so a swallowed alarm (denied exact-alarm access, OEM
 * battery managers) only delays the relock until the next tick.
 */
class AlarmRelockScheduler(
    private val context: Context,
    private val stateStore: GateStateStore,
    private val eventLog: WriteBeforeScrollEventLogStore,
    private val now: () -> Instant = Instant::now,
) : RelockSchedulerPort {

    override fun scheduleRelock(at: Instant) {
        cancelRelock()
        val current = now()
        when (val plan = RelockPlanner.plan(current, at)) {
            RelockPlanner.Plan.TooShort -> {
                stateStore.update { state ->
                    state.copy(lastErrorMessage = TooShortMessage)
                }
                eventLog.append(
                    WriteBeforeScrollEventName.RelockFailed,
                    at = current,
                    message = TooShortMessage,
                )
            }
            is RelockPlanner.Plan.At -> {
                setAlarm(plan.triggerAtEpochMillis)
                stateStore.update { state -> state.copy(lastErrorMessage = null) }
                eventLog.append(
                    WriteBeforeScrollEventName.RelockScheduled,
                    at = current,
                    message = "Relock scheduled.",
                    metadata = mapOf("unlockedUntil" to at.toString()),
                )
            }
        }
    }

    override fun cancelRelock() {
        alarmManager().cancel(pendingIntent())
    }

    @SuppressLint("MissingPermission") // SCHEDULE_EXACT_ALARM is declared; canScheduleExactAlarms guards the call.
    private fun setAlarm(triggerAtEpochMillis: Long) {
        val alarmManager = alarmManager()
        val canExact = Build.VERSION.SDK_INT < 31 || alarmManager.canScheduleExactAlarms()
        if (canExact) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtEpochMillis,
                pendingIntent(),
            )
        } else {
            // Exact-alarm access revoked (Android 14 default-deny): a windowed
            // alarm plus the watcher tick still relocks within moments.
            alarmManager.setWindow(
                AlarmManager.RTC_WAKEUP,
                triggerAtEpochMillis,
                InexactWindowMillis,
                pendingIntent(),
            )
        }
    }

    private fun alarmManager(): AlarmManager =
        context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    private fun pendingIntent(): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            RequestCode,
            Intent(context, RelockReceiver::class.java).setAction(RelockReceiver.Action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private companion object {
        const val RequestCode = 4108
        const val InexactWindowMillis = 60_000L
        const val TooShortMessage = "Unlock window is too short to schedule the relock alarm."
    }
}
