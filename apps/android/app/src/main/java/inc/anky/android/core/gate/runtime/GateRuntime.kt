package inc.anky.android.core.gate.runtime

import android.content.Context
import inc.anky.android.core.gate.GateStateStore
import inc.anky.android.core.gate.GateStorage
import inc.anky.android.core.gate.QuickPassStore
import inc.anky.android.core.gate.UnlockStateStore
import inc.anky.android.core.gate.WriteBeforeScrollEventLogStore
import inc.anky.android.core.gate.WriteBeforeScrollGateSwitchStore

/**
 * One-stop construction of the gate runtime's stores and ports over the
 * shared `anky-write-before-scroll` preferences file (WIRING-gate.md DI
 * shape). Cheap to build — `SharedPreferences` instances are process-cached
 * — so the service, receivers, and screens each build their own instead of
 * threading a singleton through components Android instantiates for us.
 */
class GateRuntime(context: Context) {
    private val appContext = context.applicationContext

    val preferences = GateStorage.preferences(appContext)

    val selectionStore = BlockedAppSelectionStore(preferences)
    val stateStore = GateStateStore(preferences)
    val gateSwitchStore = WriteBeforeScrollGateSwitchStore(preferences)
    val unlockStateStore = UnlockStateStore(preferences)
    val quickPassStore = QuickPassStore(preferences)
    val eventLog = WriteBeforeScrollEventLogStore(preferences)

    val shieldPort = AndroidShieldPort(
        selectionStore = selectionStore,
        stateStore = stateStore,
        gateSwitchStore = gateSwitchStore,
        eventLog = eventLog,
        hasEnforcementAccess = { UsageAccess.hasUsageAccess(appContext) },
        onShieldArmed = { GateRuntimeController.ensureRunning(appContext) },
    )

    val relockScheduler = AlarmRelockScheduler(
        context = appContext,
        stateStore = stateStore,
        eventLog = eventLog,
    )

    val unlockApplier = GateUnlockApplier(
        quickPassStore = quickPassStore,
        unlockStateStore = unlockStateStore,
        stateStore = stateStore,
        eventLog = eventLog,
        shieldPort = shieldPort,
        relockScheduler = relockScheduler,
    )
}
