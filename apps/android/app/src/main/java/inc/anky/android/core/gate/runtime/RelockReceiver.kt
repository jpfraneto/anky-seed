package inc.anky.android.core.gate.runtime

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import inc.anky.android.core.gate.WriteBeforeScrollShieldReconciler
import inc.anky.android.core.gate.WriteBeforeScrollUnlockStateMachine
import java.time.Instant

/**
 * Android's `DeviceActivityMonitorExtension.intervalDidEnd`: the unlock
 * window closed — re-arm the lock through the reconciler (the off-switch
 * outranks the alarm, WIRING-gate.md rule 2), mutate state only through the
 * state machine, and make sure the watcher is standing.
 */
class RelockReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Action) return
        val now = Instant.now()
        val runtime = GateRuntime(context)

        when (
            WriteBeforeScrollShieldReconciler.decision(
                gateOff = runtime.gateSwitchStore.isGateOff,
                state = runtime.stateStore.load(),
                at = now,
            )
        ) {
            WriteBeforeScrollShieldReconciler.Decision.ClearShield -> {
                // Off-switch, or the window was replaced (daily upgrade)
                // after this alarm was set: the only legal move is clearing.
                runtime.shieldPort.clearShield(now)
            }
            WriteBeforeScrollShieldReconciler.Decision.ApplyShield -> {
                // reconcileShield applies and logs relock_applied /
                // relock_failed; on success also run the state machine's
                // relock transition, exactly like the iOS monitor.
                val applied = runtime.shieldPort.reconcileShield(now)
                if (applied) {
                    runtime.stateStore.update { state ->
                        WriteBeforeScrollUnlockStateMachine.applyingRelock(state, at = now)
                    }
                }
            }
        }

        GateRuntimeController.ensureRunning(context)
    }

    companion object {
        const val Action = "inc.anky.android.gate.RELOCK"
    }
}
