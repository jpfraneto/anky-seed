package inc.anky.android.core.protocol

object AnkyParser {
    fun parse(text: String): ParsedAnky {
        val lines = text
            .replace("\r\n", "\n")
            .split("\n")
            .dropLastWhileIndexedOnce { it.isEmpty() }

        if (lines.isEmpty()) throw AnkyParseException("EMPTY_ANKY")

        val first = parseWritingLine(lines.first())
        val events = mutableListOf(AnkyEvent(deltaMs = 0, glyph = first.glyph))
        var terminalSilenceMs: Long? = null

        for (line in lines.drop(1)) {
            if (line == AnkyDuration.TerminalSilenceMs.toString()) {
                if (terminalSilenceMs != null) {
                    throw AnkyParseException("DUPLICATE_TERMINAL_SILENCE")
                }
                terminalSilenceMs = AnkyDuration.TerminalSilenceMs
                continue
            }
            if (terminalSilenceMs != null) {
                throw AnkyParseException("EVENT_AFTER_TERMINAL_SILENCE")
            }
            val parsed = parseWritingLine(line)
            events += AnkyEvent(deltaMs = parsed.time, glyph = parsed.glyph)
        }

        return ParsedAnky(
            startEpochMs = first.time,
            events = events,
            terminalSilenceMs = terminalSilenceMs,
        )
    }

    private fun parseWritingLine(line: String): ParsedLine {
        val separator = line.indexOf(' ')
        if (separator < 1) throw AnkyParseException("MALFORMED_LINE")

        val timeText = line.substring(0, separator)
        val glyph = line.substring(separator + 1)
        if (timeText.isEmpty() || !timeText.all { it in '0'..'9' }) {
            throw AnkyParseException("INVALID_TIME")
        }
        if (glyph.isEmpty()) throw AnkyParseException("MISSING_CHARACTER")
        if (!glyph.isSingleProtocolGlyph()) throw AnkyParseException("MULTI_CHARACTER_EVENT")

        val time = timeText.toLongOrNull() ?: throw AnkyParseException("UNSAFE_TIME")
        return ParsedLine(time = time, glyph = glyph)
    }

    private data class ParsedLine(val time: Long, val glyph: String)
}

private fun List<String>.dropLastWhileIndexedOnce(predicate: (String) -> Boolean): List<String> {
    if (isNotEmpty() && predicate(last())) return dropLast(1)
    return this
}

internal fun String.isSingleProtocolGlyph(): Boolean =
    isSingleGraphemeCluster()

private fun String.isSingleGraphemeCluster(): Boolean {
    if (isEmpty() || contains('\n') || contains('\r')) return false

    val codePoints = codePoints().toArray()
    if (codePoints.size == 2 && codePoints.all(::isRegionalIndicator)) return true

    var clusters = 0
    var joinsNext = false
    for (codePoint in codePoints) {
        when {
            codePoint == ZeroWidthJoiner -> {
                if (clusters == 0) {
                    clusters = 1
                } else {
                    if (joinsNext) return false
                    joinsNext = true
                }
            }
            codePoint.isAttachedMark() -> {
                if (clusters == 0) clusters = 1
            }
            joinsNext -> {
                joinsNext = false
            }
            else -> {
                clusters += 1
                if (clusters > 1) return false
            }
        }
    }
    return clusters == 1
}

private fun Int.isAttachedMark(): Boolean {
    val type = Character.getType(this)
    return type == Character.NON_SPACING_MARK.toInt() ||
        type == Character.COMBINING_SPACING_MARK.toInt() ||
        type == Character.ENCLOSING_MARK.toInt() ||
        this in VariationSelectors ||
        this in EmojiModifiers
}

private fun isRegionalIndicator(codePoint: Int): Boolean =
    codePoint in RegionalIndicators

private const val ZeroWidthJoiner = 0x200D
private val VariationSelectors = 0xFE00..0xFE0F
private val EmojiModifiers = 0x1F3FB..0x1F3FF
private val RegionalIndicators = 0x1F1E6..0x1F1FF
