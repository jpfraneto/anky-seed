package inc.anky.android.storage

import inc.anky.android.core.storage.LocalAnkyArchive
import inc.anky.android.core.storage.SessionIndexStore
import inc.anky.android.core.storage.SessionSummary
import inc.anky.android.core.storage.WritingInputStats
import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class WritingInputStatsTest {
    @get:Rule val temp = TemporaryFolder()

    @Test
    fun archivePersistsInputStatsSidecarBesideAnkyFile() {
        val directory = temp.newFolder("ankys")
        val archive = LocalAnkyArchive.forDirectory(directory)

        val saved = archive.save("1770000000000 h\n0042 i\n8000", WritingInputStats(backspaceCount = 3, enterCount = 2))

        assertEquals(WritingInputStats(3, 2), saved.inputStats)
        val sidecar = File(directory, "${saved.hash}.input-stats.json")
        assertTrue(sidecar.exists())
        val json = JSONObject(sidecar.readText(Charsets.UTF_8))
        assertEquals(3, json.getInt("backspaceCount"))
        assertEquals(2, json.getInt("enterCount"))

        // A fresh archive over the same directory reads the sidecar back.
        val reloaded = LocalAnkyArchive.forDirectory(directory).load(saved.hash)
        assertEquals(WritingInputStats(3, 2), reloaded.inputStats)
        assertEquals(WritingInputStats(3, 2), archive.list().single().inputStats)
    }

    @Test
    fun missingInputStatsSidecarLoadsAsZeroCounts() {
        val directory = temp.newFolder("ankys")
        val archive = LocalAnkyArchive.forDirectory(directory)
        val saved = archive.save("1770000000000 h\n0042 i\n8000", WritingInputStats(5, 1))

        File(directory, "${saved.hash}.input-stats.json").delete()

        assertEquals(WritingInputStats.Empty, archive.load(saved.hash).inputStats)
    }

    @Test
    fun corruptInputStatsSidecarLoadsAsZeroCounts() {
        val directory = temp.newFolder("ankys")
        val archive = LocalAnkyArchive.forDirectory(directory)
        val saved = archive.save("1770000000000 h\n0042 i\n8000", WritingInputStats(5, 1))

        File(directory, "${saved.hash}.input-stats.json").writeText("not json", Charsets.UTF_8)

        assertEquals(WritingInputStats.Empty, archive.load(saved.hash).inputStats)
    }

    @Test
    fun deleteRemovesInputStatsSidecar() {
        val directory = temp.newFolder("ankys")
        val archive = LocalAnkyArchive.forDirectory(directory)
        val saved = archive.save("1770000000000 h\n0042 i\n8000", WritingInputStats(1, 0))

        archive.delete(saved.hash)

        assertFalse(File(directory, "${saved.hash}.anky").exists())
        assertFalse(File(directory, "${saved.hash}.input-stats.json").exists())
    }

    @Test
    fun clearRemovesInputStatsSidecars() {
        val directory = temp.newFolder("ankys")
        val archive = LocalAnkyArchive.forDirectory(directory)
        archive.save("1770000000000 h\n0042 i\n8000", WritingInputStats(1, 1))

        archive.clear()

        assertEquals(0, archive.list().size)
        assertEquals(0, directory.listFiles { file -> file.name.endsWith(".input-stats.json") }!!.size)
    }

    @Test
    fun sessionSummaryCarriesInputCountsAndRoundTripsThroughIndex() {
        val archive = LocalAnkyArchive.forDirectory(temp.newFolder("ankys"))
        val index = SessionIndexStore.forFile(File(temp.newFolder("index"), "session-index.json"))
        val saved = archive.save("1770000000000 h\n0042 i\n8000", WritingInputStats(backspaceCount = 7, enterCount = 4))

        val summary = SessionSummary.make(saved, reflection = null)
        assertEquals(7, summary.backspaceCount)
        assertEquals(4, summary.enterCount)

        index.save(listOf(summary))
        val loaded = index.load().single()
        assertEquals(7, loaded.backspaceCount)
        assertEquals(4, loaded.enterCount)
    }

    @Test
    fun sessionIndexDecodesLegacyJsonWithoutInputCountsAsZero() {
        val file = File(temp.newFolder("index"), "session-index.json")
        file.writeText(
            """
            [
              {
                "hash": "${"a".repeat(64)}",
                "createdAt": "2026-02-02T02:40:00Z",
                "localFilePath": "/tmp/a.anky",
                "durationMs": 488000,
                "isComplete": true,
                "preview": "hi",
                "wordCount": 1,
                "hasReflection": false,
                "reflectionTitle": null,
                "tags": []
              }
            ]
            """.trimIndent(),
            Charsets.UTF_8,
        )

        val summary = SessionIndexStore.forFile(file).load().single()
        assertEquals(0, summary.backspaceCount)
        assertEquals(0, summary.enterCount)
        assertEquals(1, summary.wordCount)
    }
}
