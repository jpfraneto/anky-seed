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
    codePointCount(0, length) == 1 && this != "\n" && this != "\r"
