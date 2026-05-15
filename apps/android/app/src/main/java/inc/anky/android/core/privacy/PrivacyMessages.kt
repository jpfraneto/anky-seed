package inc.anky.android.core.privacy

object PrivacyMessages {
    const val AnkyCoinContractAddress = "6GsRbp2Bz9QZsoAEmUSGgTpTW7s59m7R3EGtm1FPpump"
    const val RevealReminder = "Your writing stays on this device unless you tap Ask Anky."
    const val FragmentReminder = "Fragments are local writings. They can be copied or exported, but cannot ask Anky."
    const val FreeCreditMessagePrefix = "Hi JP, I am using Anky on Android and would like free credits. Public key:"
    const val DollarAnky = "\$ANKY is informational in this app. It is not required for the writing ritual."

    fun freeCreditMessage(publicKey: String, appVersion: String): String =
        "$FreeCreditMessagePrefix $publicKey\nPlatform: Android\nApp version: $appVersion"
}
