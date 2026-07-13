package inc.anky.android.level

import inc.anky.android.core.level.AnkyLevel
import inc.anky.android.core.level.LevelChapterArtifact
import inc.anky.android.core.level.LevelSessionStat
import inc.anky.android.core.level.LevelTriggerTuning
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LevelTriggerTuningTest {
    @Test
    fun withoutHistoryFallsBackToNinetyPercent() {
        val early = AnkyLevel.progress(100)
        assertFalse(LevelTriggerTuning.shouldPrepareNextPainting(early, emptyList()))
        val late = AnkyLevel.progress(470) // 470/480 ≈ 98% of level 1
        assertTrue(LevelTriggerTuning.shouldPrepareNextPainting(late, emptyList()))
    }

    @Test
    fun withHistoryTriggersWithinOneStrongDayOfCrossing() {
        // Seven writing days of exactly 600s → p95 = 600.
        val history = List(7) { 600L } + List(21) { 0L }
        val far = AnkyLevel.progress(0) // 480s remaining < 600 → triggers immediately
        assertTrue(LevelTriggerTuning.shouldPrepareNextPainting(far, history))

        val level3 = AnkyLevel.progress(AnkyLevel.thresholdSeconds(3)) // 1260s remaining
        assertFalse(LevelTriggerTuning.shouldPrepareNextPainting(level3, history))
        val nearCrossing = AnkyLevel.progress(AnkyLevel.thresholdSeconds(4) - 599)
        assertTrue(LevelTriggerTuning.shouldPrepareNextPainting(nearCrossing, history))
    }

    @Test
    fun dailySecondsHistoryBucketsTrailingWindowOldestFirst() {
        val zone = ZoneOffset.UTC
        val nowMs = 1_770_000_000_000 // fixed instant
        val dayMs = 86_400_000L
        val history = LevelTriggerTuning.dailySecondsHistory(
            summaries = listOf(
                LevelSessionStat(hash = "a", createdAtMs = nowMs, durationMs = 60_000),
                LevelSessionStat(hash = "b", createdAtMs = nowMs, durationMs = 30_000),
                LevelSessionStat(hash = "c", createdAtMs = nowMs - dayMs, durationMs = 120_000),
                LevelSessionStat(hash = "d", createdAtMs = nowMs - 40 * dayMs, durationMs = 300_000),
            ),
            nowMs = nowMs,
            zone = zone,
        )
        assertEquals(LevelTriggerTuning.DailyOutputWindowDays, history.size)
        assertEquals(90L, history.last()) // today, most recent last
        assertEquals(120L, history[history.size - 2]) // yesterday
        assertTrue(history.dropLast(2).all { it == 0L }) // 40 days ago is outside the window
    }

    @Test
    fun distillKeepsOnlyTheCurrentChapterInChronologicalOrder() {
        val corpus = LevelTriggerTuning.distillText(
            artifacts = listOf(
                LevelChapterArtifact(createdAtMs = 1_000, reconstructedText = "old chapter"),
                LevelChapterArtifact(createdAtMs = 3_000, reconstructedText = "second piece"),
                LevelChapterArtifact(createdAtMs = 2_000, reconstructedText = "first piece"),
            ),
            sinceMs = 1_500,
        )
        assertEquals("first piece\n\n---\n\nsecond piece", corpus)
    }

    @Test
    fun distillCapsAtSixtyThousandCharactersMostRecentKept() {
        val big = "x".repeat(40_000)
        val corpus = LevelTriggerTuning.distillText(
            artifacts = listOf(
                LevelChapterArtifact(createdAtMs = 1_000, reconstructedText = big),
                LevelChapterArtifact(createdAtMs = 2_000, reconstructedText = big),
                LevelChapterArtifact(createdAtMs = 3_000, reconstructedText = big),
            ),
            sinceMs = null,
        )
        assertTrue(corpus.length <= LevelTriggerTuning.MaxDistillCharacters + 16)
        // Most recent artifact survives whole; the oldest is clipped or dropped.
        assertTrue(corpus.length > 40_000)
    }

    @Test
    fun loadingExcerptsComeFromCurrentChapterWriting() {
        val excerpts = LevelTriggerTuning.loadingExcerpts(
            artifacts = listOf(
                LevelChapterArtifact(createdAtMs = 1_770_000_000_000, reconstructedText = "old"),
                LevelChapterArtifact(createdAtMs = 1_770_000_200_000, reconstructedText = "Another piece from the chapter."),
                LevelChapterArtifact(createdAtMs = 1_770_000_100_000, reconstructedText = "This is the first painting seed."),
            ),
            sinceMs = 1_770_000_001_000,
            limit = 3,
        )

        assertFalse(excerpts.any { it.contains("old") })
        assertTrue(excerpts.any { it.contains("first painting seed") })
        assertTrue(excerpts.any { it.contains("Another piece") })
    }

    @Test
    fun excerptsNormalizeWhitespaceAndSkipShortFragments() {
        val excerpts = LevelTriggerTuning.loadingExcerpts(
            artifacts = listOf(
                LevelChapterArtifact(createdAtMs = 1, reconstructedText = "too short"),
                LevelChapterArtifact(createdAtMs = 2, reconstructedText = "many\n\nwords   spread  across\nlines here"),
            ),
            sinceMs = null,
            limit = 4,
        )
        assertEquals(listOf("many words spread across lines here"), excerpts)
    }

    @Test
    fun excerptsSpreadAcrossTheChapterWhenPlentiful() {
        val artifacts = (1..10).map { index ->
            LevelChapterArtifact(
                createdAtMs = index.toLong(),
                reconstructedText = "piece number $index with enough characters to qualify",
            )
        }
        val excerpts = LevelTriggerTuning.loadingExcerpts(artifacts, sinceMs = null, limit = 4)
        assertEquals(4, excerpts.size)
        assertTrue(excerpts.first().contains("number 1 "))
        assertTrue(excerpts.last().contains("number 10 "))
    }
}
