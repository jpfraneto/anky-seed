package inc.anky.android.core.storage

import inc.anky.android.core.protocol.AnkyDuration
import inc.anky.android.core.protocol.AnkyValidation
import inc.anky.android.core.protocol.AnkyValidator
import inc.anky.android.core.protocol.protocolGlyphsOrNull
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction

object SingleAnkyImporter {
    fun importText(
        rawText: String,
        archive: LocalAnkyArchive,
        reflectionStore: ReflectionStore,
        indexStore: SessionIndexStore,
    ): SavedAnky {
        for (candidate in importCandidates(rawText)) {
            val validation = AnkyValidator.validate(candidate)
            if (validation is AnkyValidation.Valid && validation.isComplete) {
                val saved = archive.save(candidate)
                indexStore.upsert(SessionSummary.make(saved, reflectionStore.load(saved.hash)))
                return saved
            }
        }
        error("i couldn't find a readable .anky in that.")
    }

    fun importBytes(
        bytes: ByteArray,
        archive: LocalAnkyArchive,
        reflectionStore: ReflectionStore,
        indexStore: SessionIndexStore,
    ): SavedAnky =
        importText(decodeUtf8Strict(bytes), archive, reflectionStore, indexStore)

    private fun decodeUtf8Strict(bytes: ByteArray): String =
        runCatching {
            Charsets.UTF_8
                .newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes))
                .toString()
        }.getOrNull() ?: error("That .anky file could not be read.")
}

private fun importCandidates(text: String): List<String> {
    val candidates = linkedSetOf<String>()

    fun append(candidate: String) {
        normalizedImportedAnkyText(candidate)
            .takeIf { it.isNotEmpty() }
            ?.let(candidates::add)
    }

    val prepared = text
        .replace("\r\n", "\n")
        .replace("\r", "\n")
        .replace("\uFEFF", "")
        .replace("\u200B", "")
        .replace("\u00A0", " ")

    append(prepared)
    fencedCodeBlocks(prepared).forEach(::append)
    extractedProtocolBlock(prepared)?.let(::append)

    return candidates.toList()
}

private fun fencedCodeBlocks(text: String): List<String> {
    val lines = text.split("\n")
    val blocks = mutableListOf<String>()
    var startIndex: Int? = null

    lines.forEachIndexed { index, line ->
        if (!line.trim().startsWith("```")) return@forEachIndexed
        val start = startIndex
        if (start == null) {
            startIndex = index
        } else {
            blocks += lines.subList(start + 1, index).joinToString("\n")
            startIndex = null
        }
    }

    return blocks
}

private fun extractedProtocolBlock(text: String): String? {
    val lines = text.split("\n")
    var best = emptyList<String>()
    var current = mutableListOf<String>()

    fun finishCurrent() {
        if (current.size > best.size) best = current.toList()
        current = mutableListOf()
    }

    lines.forEach { line ->
        val normalized = normalizedProtocolLine(line)
        if (normalized == null) {
            finishCurrent()
        } else {
            current += normalized
            if (normalized == AnkyDuration.TerminalSilenceMs.toString()) finishCurrent()
        }
    }
    finishCurrent()

    return best.takeIf { it.isNotEmpty() }?.joinToString("\n")
}

private fun normalizedImportedAnkyText(text: String): String =
    text
        .replace("\r\n", "\n")
        .replace("\r", "\n")
        .split("\n")
        .dropBlankEdges()
        .joinToString("\n") { line -> normalizedProtocolLine(line) ?: line }

private fun normalizedProtocolLine(rawLine: String): String? {
    val line = rawLine.trimStart()
    if (line.trim() == AnkyDuration.TerminalSilenceMs.toString()) {
        return AnkyDuration.TerminalSilenceMs.toString()
    }

    val separator = line.indexOfFirst(Char::isWhitespace)
    if (separator <= 0) return null

    val timeText = line.substring(0, separator)
    if (!timeText.all(Char::isDigit)) return null

    val characterText = line.substring(separator + 1)
    val trimmedCharacterText = characterText.trim()

    return when {
        trimmedCharacterText == "SPACE" || characterText == " " -> "$timeText SPACE"
        characterText.protocolGlyphsOrNull(maxGlyphs = 1)?.size == 1 -> "$timeText $characterText"
        trimmedCharacterText.protocolGlyphsOrNull(maxGlyphs = 1)?.size == 1 -> "$timeText $trimmedCharacterText"
        else -> null
    }
}

private fun List<String>.dropBlankEdges(): List<String> {
    var start = 0
    var end = size
    while (start < end && this[start].isBlank()) start += 1
    while (end > start && this[end - 1].isBlank()) end -= 1
    return subList(start, end)
}
