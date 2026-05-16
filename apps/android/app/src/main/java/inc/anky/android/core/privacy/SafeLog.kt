package inc.anky.android.core.privacy

import android.util.Log
import inc.anky.android.BuildConfig

object SafeLog {
    private val Forbidden = listOf(
        Regex("\\d{13} .+\\n\\d{1,} .+", RegexOption.DOT_MATCHES_ALL),
        Regex("ANKY_RECOVERY_PHRASE_V1"),
        Regex("recovery phrase", RegexOption.IGNORE_CASE),
        Regex("seed phrase", RegexOption.IGNORE_CASE),
        Regex("private key", RegexOption.IGNORE_CASE),
        Regex("signature", RegexOption.IGNORE_CASE),
        Regex("X-Anky-Signature", RegexOption.IGNORE_CASE),
        Regex("prompt", RegexOption.IGNORE_CASE),
        Regex("reflection", RegexOption.IGNORE_CASE),
    )

    fun info(tag: String, message: String, fields: Map<String, Any?> = emptyMap()) {
        if (!BuildConfig.DEBUG) return
        val safe = render(message, fields)
        if (isSafe(safe)) Log.i(tag, safe)
    }

    fun warn(tag: String, message: String, fields: Map<String, Any?> = emptyMap()) {
        val safe = render(message, fields)
        if (isSafe(safe)) Log.w(tag, safe)
    }

    fun isSafe(message: String): Boolean =
        Forbidden.none { it.containsMatchIn(message) }

    private fun render(message: String, fields: Map<String, Any?>): String {
        if (fields.isEmpty()) return message
        val rendered = fields.entries.joinToString(separator = " ") { (key, value) -> "$key=$value" }
        return "$message $rendered"
    }
}
