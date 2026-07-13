package inc.anky.android.core.gate.runtime

import inc.anky.android.core.gate.GateState
import inc.anky.android.core.gate.WriteBeforeScrollShieldReconciler
import java.time.Instant

/**
 * The pure half of the watcher: given what the platform saw (the foreground
 * package) and what the gate engine knows (off-switch + state), decide.
 * `GateWatcherService` only executes verdicts; every judgement lives here so
 * it is JVM-testable, mirroring how iOS keeps the reconciler pure.
 */
object GateWatcherPolicy {

    sealed interface Verdict {
        /** The blocked app surfaced while locked — put the door in front of it. */
        data class LaunchShield(val packageName: String) : Verdict

        /** Nothing to do. */
        data object None : Verdict
    }

    /**
     * Judge one observed foreground package. The off-switch and any active
     * unlock window both outrank the block list — the reconciler is the
     * single source of that ordering ([WriteBeforeScrollShieldReconciler]).
     */
    fun verdict(
        foregroundPackage: String?,
        blockedPackages: Set<String>,
        ownPackage: String,
        gateOff: Boolean,
        state: GateState,
        now: Instant,
    ): Verdict {
        val packageName = foregroundPackage ?: return Verdict.None
        if (packageName == ownPackage) return Verdict.None
        if (packageName !in blockedPackages) return Verdict.None
        return when (WriteBeforeScrollShieldReconciler.decision(gateOff, state, now)) {
            WriteBeforeScrollShieldReconciler.Decision.ApplyShield -> Verdict.LaunchShield(packageName)
            WriteBeforeScrollShieldReconciler.Decision.ClearShield -> Verdict.None
        }
    }

    /**
     * Belt-and-braces tick reconcile (the iOS DeviceActivityMonitor +
     * foreground-reconcile philosophy): true when the persisted state
     * disagrees with the reconciler decision and must be rewritten —
     * an expired unlock still marked open, or a shield still marked up
     * while the gate is off/unlocked. Keeping this a *disagreement* check
     * keeps the 800ms tick from rewriting preferences every pass.
     */
    fun needsStateReconcile(gateOff: Boolean, state: GateState, now: Instant): Boolean =
        when (WriteBeforeScrollShieldReconciler.decision(gateOff, state, now)) {
            WriteBeforeScrollShieldReconciler.Decision.ApplyShield -> !state.shieldActive
            WriteBeforeScrollShieldReconciler.Decision.ClearShield -> state.shieldActive
        }

    /**
     * Debounce for shield launches: never relaunch for the same package
     * within [ShieldLaunchDebounceMillis] (the activity is `singleTask`;
     * relaunching every 800ms poll would fight the window animation).
     */
    fun shouldLaunchAgain(
        lastLaunchedPackage: String?,
        lastLaunchAtMillis: Long,
        packageName: String,
        nowMillis: Long,
    ): Boolean =
        lastLaunchedPackage != packageName ||
            nowMillis - lastLaunchAtMillis >= ShieldLaunchDebounceMillis

    const val ShieldLaunchDebounceMillis = 2_000L
}
