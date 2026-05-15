package inc.anky.android.storage

import inc.anky.android.core.storage.ActiveDraftStore
import inc.anky.android.core.storage.LocalAnkyArchive
import inc.anky.android.core.storage.LocalReflection
import inc.anky.android.core.storage.ReflectionStore
import inc.anky.android.core.storage.SessionIndexStore
import inc.anky.android.core.storage.SessionSummary
import java.io.File
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class StorageTest {
    @get:Rule val temp = TemporaryFolder()

    @Test
    fun activeDraftSaveRestoreClearWorks() {
        val store = ActiveDraftStore.forDirectory(temp.newFolder("draft"))
        store.save("1770000000000 h")
        assertEquals("1770000000000 h", store.load())
        store.clear()
        assertNull(store.load())
    }

    @Test
    fun archiveSaveReadListWorks() {
        val archive = LocalAnkyArchive.forDirectory(temp.newFolder("ankys"))
        val artifact = archive.save("1770000000000 h\n0042 e\n8000")
        assertEquals("he", artifact.reconstructedText)
        assertEquals(artifact.hash, archive.load(artifact.hash).hash)
        assertEquals(1, archive.list().size)
    }

    @Test
    fun archiveRejectsNonHashLoadPaths() {
        val archive = LocalAnkyArchive.forDirectory(temp.newFolder("ankys"))
        try {
            archive.load("../session-index")
            fail("Expected invalid hash rejection")
        } catch (expected: IllegalArgumentException) {
            assertTrue(expected.message!!.contains("Invalid .anky hash."))
        }
    }

    @Test
    fun archiveDoesNotWriteInvalidAnkyFiles() {
        val directory = temp.newFolder("ankys")
        val archive = LocalAnkyArchive.forDirectory(directory)
        try {
            archive.save("not-a-timestamp h\n8000")
            fail("Expected invalid .anky rejection")
        } catch (_: Throwable) {
            assertEquals(0, directory.listFiles { file -> file.extension == "anky" }!!.size)
        }
    }

    @Test
    fun reflectionSaveReadByHashWorks() {
        val store = ReflectionStore.forDirectory(temp.newFolder("reflections"))
        val reflection = LocalReflection("abc", "Small Thread", "Here is what I saw.", Instant.EPOCH, 3)
        store.save(reflection)
        assertEquals(reflection, store.load("abc"))
    }

    @Test
    fun sessionIndexRebuildAndReflectionUpdateWorks() {
        val archive = LocalAnkyArchive.forDirectory(temp.newFolder("ankys"))
        val reflections = ReflectionStore.forDirectory(temp.newFolder("reflections"))
        val index = SessionIndexStore.forFile(File(temp.newFolder("index"), "session-index.json"))
        val artifact = archive.save("1770000000000 h\n0042 e\n8000")

        val sessions = index.rebuild(archive, reflections)
        assertEquals(1, sessions.size)
        assertEquals("he", sessions.first().preview)
        assertTrue(SessionIndexStore.groupByDay(sessions).isNotEmpty())

        index.updateReflection(artifact.hash, "Small Thread")
        assertEquals("Small Thread", index.load().first().reflectionTitle)
    }
}
