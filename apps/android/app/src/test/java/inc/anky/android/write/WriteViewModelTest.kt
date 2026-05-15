package inc.anky.android.write

import inc.anky.android.core.storage.ActiveDraftStore
import inc.anky.android.core.storage.LocalAnkyArchive
import inc.anky.android.core.storage.ReflectionStore
import inc.anky.android.core.storage.SessionIndexStore
import inc.anky.android.feature.write.WriteViewModel
import java.io.File
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

@OptIn(ExperimentalCoroutinesApi::class)
class WriteViewModelTest {
    @get:Rule val temp = TemporaryFolder()

    @Test
    fun restoredDraftClosesAfterElapsedSilenceAndArchivesCanonicalAnky() = runTest {
        val stores = stores()
        val start = 1_770_000_000_000
        stores.draft.save("$start h\n472000 e")

        WriteViewModel(
            activeDraftStore = stores.draft,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            nowMs = { start + 472000 + 8000 },
            dispatcher = StandardTestDispatcher(testScheduler),
        )
        advanceUntilIdle()

        val saved = stores.archive.list().single()
        assertEquals("$start h\n472000 e\n8000", saved.text)
        assertEquals(480000, saved.durationMs)
        assertEquals(true, saved.isComplete)
        assertNull(stores.draft.load())
        assertEquals(saved.hash, stores.index.load().single().hash)
    }

    @Test
    fun restoredClosedDraftArchivesWithoutAppendingTerminalTwice() = runTest {
        val stores = stores()
        val start = 1_770_000_000_000
        stores.draft.save("$start h\n472000 e\n8000")

        WriteViewModel(
            activeDraftStore = stores.draft,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            nowMs = { start + 480000 },
            dispatcher = StandardTestDispatcher(testScheduler),
        )
        advanceUntilIdle()

        assertEquals("$start h\n472000 e\n8000", stores.archive.list().single().text)
        assertNull(stores.draft.load())
    }

    @Test
    fun rejectedDeletionOrReplacementDoesNotMutateDraft() = runTest {
        val stores = stores()
        val start = 1_770_000_000_000
        val viewModel = WriteViewModel(
            activeDraftStore = stores.draft,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            nowMs = { start },
            dispatcher = StandardTestDispatcher(testScheduler),
        )

        viewModel.acceptGlyph("h")
        viewModel.ignoreBackspaceOrReplacement()
        viewModel.acceptGlyph("paste")

        assertEquals("$start h", stores.draft.load())
        assertEquals(0, stores.archive.list().size)
    }

    private fun TestScope.stores(): Stores {
        val root = temp.newFolder()
        return Stores(
            draft = ActiveDraftStore.forDirectory(File(root, "draft")),
            archive = LocalAnkyArchive.forDirectory(File(root, "archive")),
            reflections = ReflectionStore.forDirectory(File(root, "reflections")),
            index = SessionIndexStore.forFile(File(root, "session-index.json")),
        )
    }

    private data class Stores(
        val draft: ActiveDraftStore,
        val archive: LocalAnkyArchive,
        val reflections: ReflectionStore,
        val index: SessionIndexStore,
    )
}
