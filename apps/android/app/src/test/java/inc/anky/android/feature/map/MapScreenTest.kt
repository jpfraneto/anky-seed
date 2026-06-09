package inc.anky.android.feature.map

import inc.anky.android.core.storage.SessionSummary
import inc.anky.android.core.storage.SessionDay
import java.time.Instant
import org.junit.Assert.assertEquals
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
    fun sessionAccessibilityLabelMatchesCurrentSwiftPreviewShape() {
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

        assertEquals("quiet thread, hello from the map", label)
    }

    @Test
    fun sessionAccessibilityLabelUsesPreviewOnlyForFragments() {
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

        assertEquals("short spark", label)
        assertFalse(label.contains("anky"))
        assertFalse(label.contains("reflected"))
    }
}
