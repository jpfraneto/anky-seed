package inc.anky.android.core.privacy

object PrivacyMessages {
    const val AnkyCoinContractAddress = "6GsRbp2Bz9QZsoAEmUSGgTpTW7s59m7R3EGtm1FPpump"
    const val RevealReminder = "Your writing stays on this device unless you tap Ask Anky."
    const val FragmentReminder = "Fragments are local writings. They can be copied or exported, but cannot ask Anky."
    const val DollarAnky = "\$ANKY is informational in this app. It is not required for the writing ritual."

    fun freeCreditMessage(publicKey: String, appVersion: String): String =
        buildList {
            add("hey jp, i'd love to try anky reflections.")
            add("")
            add("my public identity is:")
            add(publicKey)
            add("")
            add("platform: android")
            if (appVersion.isNotBlank()) {
                add("")
                add("app version: $appVersion")
            }
        }.joinToString(separator = "\n")
}
