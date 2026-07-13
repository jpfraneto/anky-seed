package inc.anky.android.map

import inc.anky.android.core.storage.SavedAnky
import inc.anky.android.feature.map.ArchiveSearchIndex
import inc.anky.android.feature.map.archiveDaySections
import inc.anky.android.feature.map.archiveRowPreview
import java.io.File
import java.time.Instant
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The archive chamber's pure plumbing: the lowercased search cache keyed
 * by hash (built once per load, off-main in the screen), local-day
 * sections, and the row preview that never speaks in protocol words.
 */
class ArchiveChamberTest {

    @Test
    fun searchCacheIsLowercasedOncePerLoadAndKeyedByHash() {
        val entries = listOf(
            entry(hash = "a".repeat(64), text = "The RIVER remembers"),
            entry(hash = "b".repeat(64), text = "quiet morning pages"),
        )

        val cache = ArchiveSearchIndex.build(entries)

        assertEquals(2, cache.size)
        assertEquals("the river remembers", cache["a".repeat(64)])
        assertEquals("quiet morning pages", cache["b".repeat(64)])
    }

    @Test
    fun searchFiltersThroughTheCacheCaseInsensitively() {
        val river = entry(hash = "a".repeat(64), text = "The RIVER remembers")
        val morning = entry(hash = "b".repeat(64), text = "quiet morning pages")
        val entries = listOf(river, morning)
        val cache = ArchiveSearchIndex.build(entries)

        assertEquals(entries, ArchiveSearchIndex.filter(entries, cache, ""))
        assertEquals(entries, ArchiveSearchIndex.filter(entries, cache, "   "))
        assertEquals(listOf(river), ArchiveSearchIndex.filter(entries, cache, "RiVeR"))
        assertEquals(listOf(morning), ArchiveSearchIndex.filter(entries, cache, " morning "))
        assertEquals(emptyList<SavedAnky>(), ArchiveSearchIndex.filter(entries, cache, "absent"))
    }

    @Test
    fun searchNeverTouchesRawTextWhileTheCacheIsStillBuilding() {
        val entries = listOf(entry(hash = "a".repeat(64), text = "The RIVER remembers"))

        // An empty cache (still building off-main) hides rather than
        // falling back to lowercasing on the hot path.
        assertEquals(emptyList<SavedAnky>(), ArchiveSearchIndex.filter(entries, emptyMap(), "river"))
    }

    @Test
    fun daySectionsBucketByLocalDayWithTodayAndYesterdayFlags() {
        val zone = ZoneOffset.UTC
        val now = Instant.parse("2026-07-07T15:00:00Z")
        val todayLate = entry("a".repeat(64), "later today", Instant.parse("2026-07-07T14:00:00Z"))
        val todayEarly = entry("b".repeat(64), "earlier today", Instant.parse("2026-07-07T08:00:00Z"))
        val yesterday = entry("c".repeat(64), "yesterday", Instant.parse("2026-07-06T22:00:00Z"))
        val older = entry("d".repeat(64), "older", Instant.parse("2026-06-30T10:00:00Z"))

        val sections = archiveDaySections(
            entries = listOf(todayLate, todayEarly, yesterday, older),
            zone = zone,
            now = now,
        )

        assertEquals(3, sections.size)
        assertTrue(sections[0].isToday)
        assertFalse(sections[0].isYesterday)
        assertEquals(listOf(todayLate, todayEarly), sections[0].entries)
        assertTrue(sections[1].isYesterday)
        assertFalse(sections[1].isToday)
        assertEquals(listOf(yesterday), sections[1].entries)
        assertFalse(sections[2].isToday)
        assertFalse(sections[2].isYesterday)
        assertEquals(listOf(older), sections[2].entries)
    }

    @Test
    fun rowPreviewFlattensNewlinesAndNeverSpeaksProtocolWords() {
        assertEquals("one breath two lines", archiveRowPreview("one breath\ntwo lines"))
        assertEquals("···", archiveRowPreview("   \n  "))
        assertFalse(archiveRowPreview("").contains("Fragment"))
        assertFalse(archiveRowPreview("short spark").contains("Fragment"))
    }

    private fun entry(hash: String, text: String, createdAt: Instant = Instant.parse("2026-07-07T10:00:00Z")): SavedAnky =
        SavedAnky(
            file = File("/tmp/$hash.anky"),
            hash = hash,
            text = "protocol text",
            reconstructedText = text,
            durationMs = 480_000,
            isComplete = true,
            createdAt = createdAt,
        )
}
