package inc.anky.android.feature.gate

import androidx.annotation.DrawableRes
import inc.anky.android.R

/**
 * Package → bundled `blocked_*` icon mapping (the 16 iOS BlockedAppIcons,
 * copied to `drawable-nodpi/`). Mirrors the iOS `GateSetupView` catalog:
 * exact identifiers first, then a fuzzy contains-match on the normalized
 * package/label (identifiers of length ≤ 2 — "x" — match exactly only).
 * Anything unrecognized falls back to the app's real launcher icon.
 */
object BlockedAppIconCatalog {

    /** Exact package ids (the Android bundle-id column of the iOS map). */
    private val iconNameByPackage: Map<String, String> = mapOf(
        "com.instagram.android" to "blocked_instagram",
        "com.twitter.android" to "blocked_x",
        "com.zhiliaoapp.musically" to "blocked_tiktok",
        "com.ss.android.ugc.trill" to "blocked_tiktok",
        "com.google.android.youtube" to "blocked_youtube",
        "com.whatsapp" to "blocked_whatsapp",
        "com.android.chrome" to "blocked_chrome",
        "com.facebook.katana" to "blocked_facebook",
        "com.facebook.lite" to "blocked_facebook",
        "com.spotify.music" to "blocked_spotify",
        "com.snapchat.android" to "blocked_snapchat",
        "com.netflix.mediaclient" to "blocked_netflix",
        "com.reddit.frontpage" to "blocked_reddit",
        "com.linkedin.android" to "blocked_linkedin",
        "com.discord" to "blocked_discord",
        "com.openai.chatgpt" to "blocked_chatgpt",
        "com.anthropic.claude" to "blocked_claude",
        "org.telegram.messenger" to "blocked_telegram",
    )

    /** Fuzzy identifiers, matched against normalized package + label (iOS parity). */
    private val iconNameByIdentifier: Map<String, String> = mapOf(
        "instagram" to "blocked_instagram",
        "twitter" to "blocked_x",
        "x" to "blocked_x",
        "tiktok" to "blocked_tiktok",
        "musically" to "blocked_tiktok",
        "youtube" to "blocked_youtube",
        "whatsapp" to "blocked_whatsapp",
        "chrome" to "blocked_chrome",
        "facebook" to "blocked_facebook",
        "spotify" to "blocked_spotify",
        "snapchat" to "blocked_snapchat",
        "netflix" to "blocked_netflix",
        "reddit" to "blocked_reddit",
        "linkedin" to "blocked_linkedin",
        "discord" to "blocked_discord",
        "chatgpt" to "blocked_chatgpt",
        "openai" to "blocked_chatgpt",
        "claude" to "blocked_claude",
        "anthropic" to "blocked_claude",
        "telegram" to "blocked_telegram",
    )

    /**
     * The social apps preselected in the picker when nothing is saved yet
     * (only those actually installed are kept). Deliberately narrower than
     * the full catalog — preselecting Chrome or WhatsApp would be a trap,
     * not a kindness.
     */
    val preselectedPackages: Set<String> = setOf(
        "com.instagram.android",
        "com.twitter.android",
        "com.zhiliaoapp.musically",
        "com.ss.android.ugc.trill",
        "com.google.android.youtube",
        "com.facebook.katana",
        "com.snapchat.android",
        "com.reddit.frontpage",
    )

    /** Pure name mapping — JVM-testable without resources. */
    fun iconName(packageName: String, label: String? = null): String? {
        iconNameByPackage[packageName]?.let { return it }
        val candidates = listOfNotNull(packageName, label).map(::normalized)
        for (candidate in candidates) {
            iconNameByIdentifier[candidate]?.let { return it }
            iconNameByIdentifier.entries.firstOrNull { (identifier, _) ->
                identifier.length > 2 && candidate.length > 2 &&
                    (candidate.contains(identifier) || identifier.contains(candidate))
            }?.let { return it.value }
        }
        return null
    }

    @DrawableRes
    fun drawableRes(iconName: String): Int? = when (iconName) {
        "blocked_instagram" -> R.drawable.blocked_instagram
        "blocked_x" -> R.drawable.blocked_x
        "blocked_tiktok" -> R.drawable.blocked_tiktok
        "blocked_youtube" -> R.drawable.blocked_youtube
        "blocked_whatsapp" -> R.drawable.blocked_whatsapp
        "blocked_chrome" -> R.drawable.blocked_chrome
        "blocked_facebook" -> R.drawable.blocked_facebook
        "blocked_spotify" -> R.drawable.blocked_spotify
        "blocked_snapchat" -> R.drawable.blocked_snapchat
        "blocked_netflix" -> R.drawable.blocked_netflix
        "blocked_reddit" -> R.drawable.blocked_reddit
        "blocked_linkedin" -> R.drawable.blocked_linkedin
        "blocked_discord" -> R.drawable.blocked_discord
        "blocked_chatgpt" -> R.drawable.blocked_chatgpt
        "blocked_claude" -> R.drawable.blocked_claude
        "blocked_telegram" -> R.drawable.blocked_telegram
        else -> null
    }

    @DrawableRes
    fun iconResFor(packageName: String, label: String? = null): Int? =
        iconName(packageName, label)?.let(::drawableRes)

    private fun normalized(value: String): String =
        value.lowercase().filter { it.isLetterOrDigit() }
}
