package inc.anky.android.core.gate

import android.content.SharedPreferences

/**
 * The writer's name and the anchor sentence collected during onboarding —
 * the one line they want to see before the feed. On iOS this deliberately
 * stays out of App Group storage so shield extensions can never read it;
 * on Android the same boundary holds by composing the shield arrival
 * message here and handing only the composed line to the shield surface.
 */
class WritingAnchorStore(
    private val preferences: SharedPreferences,
) {
    val writerName: String?
        get() = normalized(preferences.getString(WriterNameKey, null)) ?: DefaultWriterName

    val anchorSentence: String?
        get() = normalized(preferences.getString(AnchorSentenceKey, null))

    fun save(writerName: String?, anchorSentence: String?) {
        store(normalized(writerName), WriterNameKey)
        store(normalized(anchorSentence), AnchorSentenceKey)
    }

    /** The line Anky shows when the user arrives from a blocked app. */
    val anchorReminderLine: String?
        get() {
            val anchorSentence = anchorSentence ?: return null
            val writerName = writerName
            return if (writerName != null) {
                "$writerName, remember: “$anchorSentence”"
            } else {
                "remember: “$anchorSentence”"
            }
        }

    /**
     * The full message for a shield arrival — the anchor if one exists,
     * otherwise a plain invitation. Composed here so the shield surface
     * never needs the raw anchor.
     */
    val shieldArrivalMessage: String
        get() {
            val anchorReminderLine = anchorReminderLine
            return if (anchorReminderLine != null) {
                "$anchorReminderLine\nWrite one true sentence to unlock."
            } else {
                "Write one true thing before the feed gets in."
            }
        }

    private fun store(value: String?, key: String) {
        if (value != null) {
            preferences.edit().putString(key, value).apply()
        } else {
            preferences.edit().remove(key).apply()
        }
    }

    private fun normalized(value: String?): String? =
        value?.trim()?.takeIf { it.isNotEmpty() }

    companion object {
        const val WriterNameKey = "anky.writerName"
        const val AnchorSentenceKey = "anky.wbs.anchorSentence"
        const val DefaultWriterName = "You"
    }
}
