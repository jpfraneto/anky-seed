package inc.anky.android.core.gate

import android.content.SharedPreferences

/**
 * Tracks the first successful Write Before Scroll gate: the first time the
 * user wrote and applied an unlock. Non-private summary state.
 */
class FirstGateStore(
    private val preferences: SharedPreferences,
) {
    val hasCompletedFirstGate: Boolean
        get() = preferences.getBoolean(HasCompletedFirstGateKey, false)

    fun markFirstGateCompleted() {
        preferences.edit().putBoolean(HasCompletedFirstGateKey, true).apply()
    }

    /**
     * Hook for the future post-first-gate subscription pitch: the pitch may
     * appear only after the ritual has been experienced once, and only once.
     */
    val shouldShowPostFirstGatePaywall: Boolean
        get() = hasCompletedFirstGate && !preferences.getBoolean(PostFirstGatePaywallSeenKey, false)

    fun markPostFirstGatePaywallSeen() {
        preferences.edit().putBoolean(PostFirstGatePaywallSeenKey, true).apply()
    }

    companion object {
        const val HasCompletedFirstGateKey = "anky.wbs.hasCompletedFirstGate"
        const val PostFirstGatePaywallSeenKey = "anky.wbs.postFirstGatePaywallSeen"
    }
}
