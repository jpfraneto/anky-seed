package inc.anky.android.core.gate

import android.content.SharedPreferences
import java.time.Instant
import org.json.JSONObject

/**
 * Android port of iOS `WriteBeforeScrollScreenTimeState`: the shared gate
 * runtime state. The shape is kept 1:1 with iOS so the reconciler, state
 * machine, and signal snapshot stay identical; Android's runtime maps its
 * own concepts onto the fields (see WIRING-gate.md):
 * - selectedApplicationCount → number of blocked packages
 * - selectedCategoryCount / selectedWebDomainCount → 0 until Android grows
 *   equivalents (kept for shape parity)
 */
data class GateState(
    val selectedApplicationCount: Int = 0,
    val selectedCategoryCount: Int = 0,
    val selectedWebDomainCount: Int = 0,
    val unlockTierRawValue: String? = null,
    val unlockedUntil: Instant? = null,
    val unlockSourceRawValue: String? = null,
    val shieldActive: Boolean = false,
    val pendingInterventionRequestedAt: Instant? = null,
    val lastRelockedAt: Instant? = null,
    val lastErrorMessage: String? = null,
    val updatedAt: Instant = Instant.now(),
) {
    val hasSelection: Boolean
        get() = selectedApplicationCount > 0 || selectedCategoryCount > 0 || selectedWebDomainCount > 0

    fun isUnlocked(at: Instant = Instant.now()): Boolean {
        val unlockedUntil = unlockedUntil ?: return false
        return at.isBefore(unlockedUntil)
    }
}

class GateStateStore(
    private val preferences: SharedPreferences,
    private val now: () -> Instant = Instant::now,
) {
    fun load(): GateState {
        val raw = preferences.getString(Key, null) ?: return GateState()
        return runCatching {
            val json = JSONObject(raw)
            GateState(
                selectedApplicationCount = json.optInt("selectedApplicationCount", 0),
                selectedCategoryCount = json.optInt("selectedCategoryCount", 0),
                selectedWebDomainCount = json.optInt("selectedWebDomainCount", 0),
                unlockTierRawValue = json.optionalString("unlockTierRawValue"),
                unlockedUntil = json.optionalInstant("unlockedUntil"),
                unlockSourceRawValue = json.optionalString("unlockSourceRawValue"),
                shieldActive = json.optBoolean("shieldActive", false),
                pendingInterventionRequestedAt = json.optionalInstant("pendingInterventionRequestedAt"),
                lastRelockedAt = json.optionalInstant("lastRelockedAt"),
                lastErrorMessage = json.optionalString("lastErrorMessage"),
                updatedAt = json.optionalInstant("updatedAt") ?: Instant.now(),
            )
        }.getOrDefault(GateState())
    }

    fun save(state: GateState) {
        val json = JSONObject()
            .put("selectedApplicationCount", state.selectedApplicationCount)
            .put("selectedCategoryCount", state.selectedCategoryCount)
            .put("selectedWebDomainCount", state.selectedWebDomainCount)
            .put("shieldActive", state.shieldActive)
            .put("updatedAt", state.updatedAt.toString())
        state.unlockTierRawValue?.let { json.put("unlockTierRawValue", it) }
        state.unlockedUntil?.let { json.put("unlockedUntil", it.toString()) }
        state.unlockSourceRawValue?.let { json.put("unlockSourceRawValue", it) }
        state.pendingInterventionRequestedAt?.let { json.put("pendingInterventionRequestedAt", it.toString()) }
        state.lastRelockedAt?.let { json.put("lastRelockedAt", it.toString()) }
        state.lastErrorMessage?.let { json.put("lastErrorMessage", it) }
        preferences.edit().putString(Key, json.toString()).apply()
    }

    fun update(mutate: (GateState) -> GateState) {
        save(mutate(load()).copy(updatedAt = now()))
    }

    private companion object {
        const val Key = "writeBeforeScroll.screenTimeState.v1"

        fun JSONObject.optionalString(name: String): String? =
            if (has(name)) getString(name) else null

        fun JSONObject.optionalInstant(name: String): Instant? =
            optionalString(name)?.let(Instant::parse)
    }
}

/**
 * The explicit gate off-switch (2026-07-06): once the writer turns the
 * gate off, nothing re-arms it — not the foreground reconcile, not the
 * relock alarm, not saving a new app selection — until they turn it
 * back on.
 */
class WriteBeforeScrollGateSwitchStore(
    private val preferences: SharedPreferences,
) {
    val isGateOff: Boolean
        get() = preferences.getBoolean(Key, false)

    fun setGateOff(isOff: Boolean) {
        preferences.edit().putBoolean(Key, isOff).apply()
    }

    private companion object {
        const val Key = "writeBeforeScroll.gateOff.v1"
    }
}

/**
 * The reconcile decision, kept pure so the off-switch behavior is
 * testable without the platform runtime: while the gate is off the only
 * legal move is clearing — the shield must never re-arm behind the
 * writer's back.
 */
object WriteBeforeScrollShieldReconciler {
    enum class Decision {
        ClearShield,
        ApplyShield,
    }

    fun decision(
        gateOff: Boolean,
        state: GateState,
        at: Instant = Instant.now(),
    ): Decision {
        if (gateOff) {
            return Decision.ClearShield
        }
        if (state.isUnlocked(at)) {
            return Decision.ClearShield
        }
        return Decision.ApplyShield
    }
}

enum class WriteBeforeScrollUnlockSource(val rawValue: String) {
    Writing("writing"),
    Test("test"),

    /**
     * The 30-second emergency breath (phase-2 §2). Grants the day without
     * writing and never consumes a Quick Pass.
     */
    Emergency("emergency"),
}

object WriteBeforeScrollUnlockStateMachine {
    fun applyingUnlock(
        tierRawValue: String,
        unlockedUntil: Instant,
        source: WriteBeforeScrollUnlockSource,
        state: GateState,
    ): GateState = state.copy(
        unlockTierRawValue = tierRawValue,
        unlockedUntil = unlockedUntil,
        unlockSourceRawValue = source.rawValue,
        shieldActive = false,
        lastErrorMessage = null,
    )

    fun forcingLock(state: GateState, at: Instant): GateState = state.copy(
        unlockTierRawValue = null,
        unlockedUntil = null,
        unlockSourceRawValue = null,
        shieldActive = true,
        lastRelockedAt = at,
        lastErrorMessage = null,
    )

    fun applyingRelock(state: GateState, at: Instant): GateState = forcingLock(state, at)
}
