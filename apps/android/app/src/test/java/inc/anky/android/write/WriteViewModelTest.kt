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
    fun completedHashCanBeConsumedAfterRevealNavigation() = runTest {
        val stores = stores()
        val start = 1_770_000_000_000
        stores.draft.save("$start h\n472000 e")
        val viewModel = WriteViewModel(
            activeDraftStore = stores.draft,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            nowMs = { start + 472000 + 8000 },
            dispatcher = StandardTestDispatcher(testScheduler),
        )
        advanceUntilIdle()

        val completedHash = viewModel.state.value.completedHash
        viewModel.consumeCompletedHash()

        assertEquals(stores.archive.list().single().hash, completedHash)
        assertNull(viewModel.state.value.completedHash)
    }

    @Test
    fun completedSessionResetsWriteStateLikeIos() = runTest {
        val stores = stores()
        val start = 1_770_000_000_000
        stores.draft.save("$start h\n472000 e")
        val viewModel = WriteViewModel(
            activeDraftStore = stores.draft,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            nowMs = { start + 472000 + 8000 },
            dispatcher = StandardTestDispatcher(testScheduler),
        )
        advanceUntilIdle()

        val completedHash = viewModel.state.value.completedHash

        assertEquals(stores.archive.list().single().hash, completedHash)
        assertEquals("", viewModel.state.value.displayedText)
        assertEquals("", viewModel.state.value.latestGlyph)
        assertEquals(0, viewModel.state.value.acceptedGlyphCount)
        assertEquals(0, viewModel.state.value.elapsedMs)
        assertEquals(0, viewModel.state.value.silenceElapsedMs)
        assertEquals(8000, viewModel.state.value.silenceRemainingMs)
        assertEquals(0f, viewModel.state.value.progress)
    }

    @Test
    fun saveFailureShowsIosErrorCopyAndPreservesClosedDraft() = runTest {
        val root = temp.newFolder()
        val archiveFile = temp.newFile("archive-is-not-a-directory")
        val draft = ActiveDraftStore.forDirectory(File(root, "draft"))
        val reflections = ReflectionStore.forDirectory(File(root, "reflections"))
        val index = SessionIndexStore.forFile(File(root, "session-index.json"))
        val start = 1_770_000_000_000
        draft.save("$start h\n472000 e")

        val viewModel = WriteViewModel(
            activeDraftStore = draft,
            archive = LocalAnkyArchive.forDirectory(archiveFile),
            reflectionStore = reflections,
            indexStore = index,
            nowMs = { start + 472000 + 8000 },
            dispatcher = StandardTestDispatcher(testScheduler),
        )
        advanceUntilIdle()

        assertEquals("Could not save this .anky.", viewModel.state.value.errorMessage)
        assertEquals("$start h\n472000 e\n8000", draft.load())
        assertEquals(0, index.load().size)
    }

    @Test
    fun invalidRestoredDraftShowsIosErrorCopyAndLeavesDraftUntouched() = runTest {
        val stores = stores()
        stores.draft.save("not-a-timestamp h")

        val viewModel = WriteViewModel(
            activeDraftStore = stores.draft,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            dispatcher = StandardTestDispatcher(testScheduler),
        )
        advanceUntilIdle()

        assertEquals("Could not restore the active draft.", viewModel.state.value.errorMessage)
        assertEquals("not-a-timestamp h", stores.draft.load())
        assertEquals(0, stores.archive.list().size)
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

    @Test
    fun committedSwipeGlyphsDistributeElapsedTimeAcrossTheWord() = runTest {
        val stores = stores()
        var now = 1_770_000_000_000
        val viewModel = WriteViewModel(
            activeDraftStore = stores.draft,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            nowMs = { now },
            dispatcher = StandardTestDispatcher(testScheduler),
        )

        viewModel.acceptGlyph("h")
        now += 120
        viewModel.acceptGlyphs(listOf("e", "y", "!"))

        assertEquals(
            "1770000000000 h\n40 e\n40 y\n40 !",
            stores.draft.load(),
        )
    }

    @Test
    fun abandonIfEmptyClearsDraftButStartedSessionPersists() = runTest {
        val stores = stores()
        val start = 1_770_000_000_000
        stores.draft.save("")
        val emptyViewModel = WriteViewModel(
            activeDraftStore = stores.draft,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            nowMs = { start },
            dispatcher = StandardTestDispatcher(testScheduler),
        )

        emptyViewModel.abandonIfEmpty()

        assertNull(stores.draft.load())

        val startedViewModel = WriteViewModel(
            activeDraftStore = stores.draft,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            nowMs = { start },
            dispatcher = StandardTestDispatcher(testScheduler),
        )
        startedViewModel.acceptGlyph("h")
        startedViewModel.abandonIfEmpty()

        assertEquals("$start h", stores.draft.load())
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
