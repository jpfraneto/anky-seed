package inc.anky.android.core.storage

import inc.anky.android.core.protocol.AnkyParser
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction

object SingleAnkyImporter {
    fun importText(
        rawText: String,
        archive: LocalAnkyArchive,
        reflectionStore: ReflectionStore,
        indexStore: SessionIndexStore,
    ): SavedAnky {
        AnkyParser.parse(rawText)
        val saved = archive.save(rawText)
        indexStore.upsert(SessionSummary.make(saved, reflectionStore.load(saved.hash)))
        return saved
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
