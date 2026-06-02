package inc.anky.android.feature.map

import inc.anky.android.core.storage.SessionSummary
import inc.anky.android.core.storage.SessionDay
import java.time.Instant
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MapScreenTest {
    @Test
    fun dayAccessibilityLabelMatchesSwiftTrailNodeShape() {
        val label = dayAccessibilityLabel(
            SessionDay(
                dayEpochMs = Instant.parse("2026-05-31T00:00:00Z").toEpochMilli(),
                sessions = emptyList(),
                completeCount = 0,
                fragmentCount = 0,
                reflectionCount = 0,
                dayIndex = 1,
                dayInRegion = 1,
            ),
        )

        assertTrue(label.endsWith(", No writing"))
    }

    @Test
    fun dayAccessibilityLabelIncludesTrailActivitySummary() {
        val label = dayAccessibilityLabel(
            SessionDay(
                dayEpochMs = Instant.parse("2026-05-31T00:00:00Z").toEpochMilli(),
                sessions = listOf(
                    SessionSummary(
                        hash = "c".repeat(64),
                        createdAt = Instant.parse("2026-05-31T19:50:00Z"),
                        localFilePath = "/tmp/c.anky",
                        durationMs = 490_000,
                        isComplete = true,
                        preview = "showed up",
                        wordCount = 2,
                        hasReflection = false,
                        reflectionTitle = null,
                    ),
                ),
                completeCount = 1,
                fragmentCount = 0,
                reflectionCount = 0,
                dayIndex = 1,
                dayInRegion = 1,
            ),
        )

        assertTrue(label.endsWith(", Showed up"))
    }

    @Test
    fun sessionAccessibilityLabelMatchesSwiftMetadataShape() {
        val label = sessionAccessibilityLabel(
            SessionSummary(
                hash = "a".repeat(64),
                createdAt = Instant.parse("2026-05-31T19:50:00Z"),
                localFilePath = "/tmp/a.anky",
                durationMs = 490_000,
                isComplete = true,
                preview = "hello from the map",
                wordCount = 4,
                hasReflection = true,
                reflectionTitle = "  Quiet Thread  ",
            ),
        )

        assertTrue(label.startsWith("quiet thread, hello from the map, "))
        assertTrue(label.contains("8m 10s"))
        assertTrue(label.contains("4 words"))
        assertTrue(label.endsWith("anky · reflected"))
    }

    @Test
    fun sessionAccessibilityLabelOmitsReflectionAndAnkyForFragments() {
        val label = sessionAccessibilityLabel(
            SessionSummary(
                hash = "b".repeat(64),
                createdAt = Instant.parse("2026-05-31T19:50:00Z"),
                localFilePath = "/tmp/b.anky",
                durationMs = 45_000,
                isComplete = false,
                preview = "short spark",
                wordCount = 2,
                hasReflection = false,
                reflectionTitle = null,
            ),
        )

        assertTrue(label.startsWith("short spark, "))
        assertTrue(label.contains("0m 45s"))
        assertTrue(label.contains("2 words"))
        assertFalse(label.contains("anky"))
        assertFalse(label.contains("reflected"))
    }
}
