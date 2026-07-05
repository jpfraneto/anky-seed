package inc.anky.android.core.protocol

object AnkyReconstructor {
    fun reconstructText(parsed: ParsedAnky): String =
        parsed.events.joinToString(separator = "") { it.glyph }
}
