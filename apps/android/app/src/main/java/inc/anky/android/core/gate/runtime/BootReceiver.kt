package inc.anky.android.core.gate.runtime

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.time.Instant

/**
 * The iOS shield survives reboot because the OS owns it; Android's watcher
 * must stand itself back up. On BOOT_COMPLETED:
 *  - re-arm the relock alarm when an unlock window is still open (alarms do
 *    not survive reboot),
 *  - reconcile the shield state (an unlock that expired mid-reboot relocks
 *    here),
 *  - restart the watcher service (BOOT_COMPLETED is an exempted
 *    foreground-service start).
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val now = Instant.now()
        val runtime = GateRuntime(context)

        val unlockedUntil = runtime.stateStore.load().unlockedUntil
        if (!runtime.gateSwitchStore.isGateOff && unlockedUntil != null && unlockedUntil.isAfter(now)) {
            runtime.relockScheduler.scheduleRelock(at = unlockedUntil)
        }

        runtime.shieldPort.reconcileShield(now)
        GateRuntimeController.ensureRunning(context)
    }
}
