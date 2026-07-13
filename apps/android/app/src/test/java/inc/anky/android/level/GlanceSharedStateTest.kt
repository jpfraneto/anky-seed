package inc.anky.android.level

import inc.anky.android.core.level.GlanceSharedState
import inc.anky.android.core.level.GlanceSnapshot
import java.io.File
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GlanceSharedStateTest {
    private fun filesDir(): File =
        File(System.getProperty("java.io.tmpdir"), "anky-glance-${UUID.randomUUID()}").also { it.mkdirs() }

    @Test
    fun writeThenLoadRoundTripsSnapshotAndPrunesStaleFrames() {
        val filesDir = filesDir()
        val first = GlanceSnapshot(
            level = 2,
            percent = 40,
            updatedAtMs = 1_000,
            imageFile = GlanceSharedState.imageFileName(2, 40),
            isPlaceholder = false,
            isAtBoundary = false,
        )
        GlanceSharedState.write(filesDir, first, byteArrayOf(0x1))
        assertEquals(first, GlanceSharedState.loadSnapshot(filesDir))
        assertTrue(GlanceSharedState.imageFile(filesDir, first.imageFile).exists())

        val second = first.copy(percent = 55, imageFile = GlanceSharedState.imageFileName(2, 55), isAtBoundary = true)
        GlanceSharedState.write(filesDir, second, byteArrayOf(0x2))
        assertEquals(second, GlanceSharedState.loadSnapshot(filesDir))
        assertTrue(GlanceSharedState.imageFile(filesDir, second.imageFile).exists())
        // Stale painting frames are pruned; the trial thumb is untouched.
        assertFalse(GlanceSharedState.imageFile(filesDir, first.imageFile).exists())
    }

    @Test
    fun oldSnapshotsWithoutBoundaryFieldStillDecode() {
        val filesDir = filesDir()
        val directory = GlanceSharedState.directory(filesDir)
        directory.mkdirs()
        File(directory, GlanceSharedState.SnapshotFileName).writeText(
            """{"level":1,"percent":10,"updatedAtMs":5,"imageFile":"painting-1-10.png","isPlaceholder":true}""",
        )
        val snapshot = GlanceSharedState.loadSnapshot(filesDir)
        assertEquals(1, snapshot?.level)
        assertNull(snapshot?.isAtBoundary)
    }

    @Test
    fun missingOrMalformedSnapshotLoadsAsNull() {
        val filesDir = filesDir()
        assertNull(GlanceSharedState.loadSnapshot(filesDir))
        val directory = GlanceSharedState.directory(filesDir)
        directory.mkdirs()
        File(directory, GlanceSharedState.SnapshotFileName).writeText("not-json")
        assertNull(GlanceSharedState.loadSnapshot(filesDir))
    }

    @Test
    fun trialThumbWritesBesideTheSnapshot() {
        val filesDir = filesDir()
        GlanceSharedState.writeTrialThumb(filesDir, byteArrayOf(0x7))
        assertTrue(File(GlanceSharedState.directory(filesDir), GlanceSharedState.TrialThumbFileName).exists())
    }
}
