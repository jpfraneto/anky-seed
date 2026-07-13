package inc.anky.android.core.gate.runtime

import inc.anky.android.core.gate.GateStateStore
import inc.anky.android.core.gate.ShieldPort
import inc.anky.android.core.gate.WriteBeforeScrollEventLogStore
import inc.anky.android.core.gate.WriteBeforeScrollEventName
import inc.anky.android.core.gate.WriteBeforeScrollGateSwitchStore
import inc.anky.android.core.gate.WriteBeforeScrollShieldReconciler
import java.time.Instant

/**
 * Android's `ManagedSettingsStore`: where iOS hands the OS a shield to
 * render, Android *marks* the shield state and lets [GateWatcherService]
 * enforce it (launching the shield activity over blocked apps while
 * `shieldActive`). Port of iOS `WriteBeforeScrollShieldController`, minus
 * the OS calls: same guards, same state writes, same transition-only
 * `shield_applied` / `shield_cleared` logging.
 *
 * @param hasEnforcementAccess Android's stand-in for the iOS Screen Time
 *   authorization guard: usage access. Injected so the port stays
 *   JVM-testable.
 * @param onShieldArmed hook for the runtime to (re)start the watcher after
 *   an apply — [GateRuntimeController.ensureRunning] in production.
 */
class AndroidShieldPort(
    private val selectionStore: BlockedAppSelectionStore,
    private val stateStore: GateStateStore,
    private val gateSwitchStore: WriteBeforeScrollGateSwitchStore,
    private val eventLog: WriteBeforeScrollEventLogStore,
    private val hasEnforcementAccess: () -> Boolean = { true },
    private val onShieldArmed: () -> Unit = {},
) : ShieldPort {

    override fun applyShield(now: Instant): Boolean {
        // The off-switch outranks every apply path — including the relock
        // alarm, which calls applyShield directly (iOS decision 2026-07-06).
        if (gateSwitchStore.isGateOff) {
            clearShield(now)
            return false
        }
        if (!hasEnforcementAccess()) {
            clearShield(now)
            stateStore.update { state ->
                state.copy(
                    lastErrorMessage = "Usage access is required before selected apps can be locked.",
                )
            }
            eventLog.append(
                WriteBeforeScrollEventName.RelockFailed,
                at = now,
                message = "Usage access is not granted.",
            )
            return false
        }

        val selection = selectionStore.load()
        if (selection.isEmpty()) {
            clearShield(now)
            stateStore.update { state ->
                state.copy(
                    lastErrorMessage =
                        "No apps selected yet. Choose apps in gate setup before turning the gate on.",
                )
            }
            eventLog.append(
                WriteBeforeScrollEventName.RelockFailed,
                at = now,
                message = "No selected app to shield.",
            )
            return false
        }

        val wasShieldActive = stateStore.load().shieldActive
        stateStore.update { state ->
            state.copy(
                selectedApplicationCount = selection.size,
                selectedCategoryCount = 0,
                selectedWebDomainCount = 0,
                shieldActive = true,
                unlockedUntil = null,
                unlockTierRawValue = null,
                unlockSourceRawValue = null,
                lastErrorMessage = null,
                lastRelockedAt = now,
            )
        }
        eventLog.appendShieldTransition(
            wasShieldActive = wasShieldActive,
            isShieldActive = true,
            at = now,
            metadata = mapOf("apps" to "${selection.size}"),
        )
        onShieldArmed()
        return true
    }

    override fun clearShield(now: Instant) {
        val wasShieldActive = stateStore.load().shieldActive
        stateStore.update { state -> state.copy(shieldActive = false) }
        eventLog.appendShieldTransition(
            wasShieldActive = wasShieldActive,
            isShieldActive = false,
            at = now,
        )
    }

    /**
     * Port of iOS `reconcileShield`: obey the pure decision, and log
     * `relock_applied` when an expired unlock window is what re-armed us.
     */
    fun reconcileShield(now: Instant = Instant.now()): Boolean {
        val state = stateStore.load()
        return when (
            WriteBeforeScrollShieldReconciler.decision(
                gateOff = gateSwitchStore.isGateOff,
                state = state,
                at = now,
            )
        ) {
            WriteBeforeScrollShieldReconciler.Decision.ClearShield -> {
                clearShield(now)
                false
            }
            WriteBeforeScrollShieldReconciler.Decision.ApplyShield -> {
                val hadExpiredUnlock = state.unlockedUntil != null
                val applied = applyShield(now)
                if (hadExpiredUnlock && applied) {
                    eventLog.append(WriteBeforeScrollEventName.RelockApplied, at = now)
                }
                applied
            }
        }
    }
}
