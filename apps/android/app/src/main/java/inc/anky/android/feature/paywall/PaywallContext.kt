package inc.anky.android.feature.paywall

/**
 * Which words the paywall room speaks. Copy only — one palette, one layout,
 * exactly like the iOS `PaywallView.Context`: the onboarding and lapsed
 * variants are the same room with different words, and a veil launch keeps
 * its funnel origin so `paywall_shown {origin}` stays honest.
 *
 * Ported from iOS `Anky/Purchases/PaywallView.swift` (`PaywallView.Context`).
 */
sealed class PaywallContext {

    /** Screen 10 of onboarding, between the journey map and notifications. */
    data object Onboarding : PaywallContext()

    /** Re-entry after the trial expired unconverted or the subscription ended. */
    data object Lapsed : PaywallContext()

    /**
     * Launched from a veil or boundary surface (phase-3). [origin] is the
     * funnel's `paywall_shown {origin}` tag — e.g. "reflection", "ceremony",
     * "journey", "widget", "quick_action", "free_target_moment".
     */
    data class Veil(val origin: String) : PaywallContext()

    /** The `paywall_shown {origin}` tag this context reports. */
    val funnelOrigin: String
        get() = when (this) {
            Onboarding -> "onboarding"
            Lapsed -> "lapsed"
            is Veil -> origin
        }
}

/**
 * Funnel event names the paywall emits, matching the iOS `AnkyFunnel`
 * registry (`LevelSyncClient.swift`). The paywall reports through callbacks
 * — the level workstream owns the real funnel client; wiring adapts.
 */
object PaywallFunnel {
    const val PAYWALL_SHOWN = "paywall_shown"
    const val TRIAL_STARTED = "trial_started"
    const val SUBSCRIBED = "subscribed"
}
