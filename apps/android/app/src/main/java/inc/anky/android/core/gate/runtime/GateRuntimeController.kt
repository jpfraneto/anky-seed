package inc.anky.android.core.gate.runtime

import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import inc.anky.android.core.gate.WriteBeforeScrollEventName
import inc.anky.android.core.gate.WriteBeforeScrollUnlockStateMachine
import java.time.Instant

/**
 * The runtime's on/off lever. Everything the app needs to do to the gate
 * from UI or receivers goes through here:
 *
 *  - [ensureRunning]/[stop]: keep [GateWatcherService] alive exactly while
 *    the gate is armed (not switched off, apps selected). The service stays
 *    up through unlock windows — it is the relock's belt-and-braces, and a
 *    running FGS is exempt from background-start restrictions when the
 *    relock alarm fires.
 *  - [turnGateOn]: iOS `forceLock` — the way in, and the way back from the
 *    off-switch.
 *  - [turnGateOff]: iOS `turnGateOff` — the honest exit; nothing re-arms
 *    until [turnGateOn].
 *  - [saveSelection]: iOS `saveSelection` — persist + log + reconcile
 *    (the reconciler keeps the off-switch outranking the save).
 */
object GateRuntimeController {

    fun shouldRun(context: Context): Boolean {
        val runtime = GateRuntime(context)
        return !runtime.gateSwitchStore.isGateOff && runtime.selectionStore.hasSelection
    }

    fun ensureRunning(context: Context) {
        if (!shouldRun(context)) {
            stop(context)
            return
        }
        runCatching {
            ContextCompat.startForegroundService(context, serviceIntent(context))
        }
        // A background-start denial is survivable: the service also starts
        // from MainActivity's reconcile hook next time the app is opened.
    }

    fun stop(context: Context) {
        context.stopService(serviceIntent(context))
    }

    fun turnGateOn(context: Context, now: Instant = Instant.now()) {
        val runtime = GateRuntime(context)
        runtime.gateSwitchStore.setGateOff(false)
        runtime.unlockStateStore.clearUnlock()
        runtime.relockScheduler.cancelRelock()
        runtime.stateStore.update { state ->
            WriteBeforeScrollUnlockStateMachine.forcingLock(state, at = now)
        }
        runtime.shieldPort.applyShield(now)
        ensureRunning(context)
    }

    fun turnGateOff(context: Context, now: Instant = Instant.now()) {
        val runtime = GateRuntime(context)
        runtime.gateSwitchStore.setGateOff(true)
        runtime.relockScheduler.cancelRelock()
        runtime.shieldPort.clearShield(now)
        // iOS logs this reason explicitly on top of the transition event.
        runtime.eventLog.append(
            WriteBeforeScrollEventName.ShieldCleared,
            at = now,
            metadata = mapOf("reason" to "gateSwitchOff"),
        )
        stop(context)
    }

    fun saveSelection(context: Context, apps: List<BlockedApp>, now: Instant = Instant.now()) {
        val runtime = GateRuntime(context)
        runtime.selectionStore.save(apps, now)
        runtime.eventLog.append(
            WriteBeforeScrollEventName.AppSelectionSaved,
            at = now,
            metadata = mapOf("apps" to "${apps.size}"),
        )
        runtime.shieldPort.reconcileShield(now)
        ensureRunning(context)
    }

    /** App-foreground reconcile point (WIRING-gate.md rule 2). */
    fun reconcileOnAppActive(context: Context, now: Instant = Instant.now()) {
        GateRuntime(context).shieldPort.reconcileShield(now)
        ensureRunning(context)
    }

    private fun serviceIntent(context: Context): Intent =
        Intent(context, GateWatcherService::class.java)
}
