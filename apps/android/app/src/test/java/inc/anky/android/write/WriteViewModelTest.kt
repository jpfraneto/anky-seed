package inc.anky.android.write

import inc.anky.android.core.identity.RecoveryPhrase
import inc.anky.android.core.identity.WriterIdentity
import inc.anky.android.core.mirror.MirrorIntent
import inc.anky.android.core.mirror.MirrorResponsePayload
import inc.anky.android.core.protocol.AnkyHasher
import inc.anky.android.core.storage.ActiveDraftStore
import inc.anky.android.core.storage.LocalAnkyArchive
import inc.anky.android.core.storage.ReflectionStore
import inc.anky.android.core.storage.SessionIndexStore
import inc.anky.android.feature.write.WriteViewModel
import java.io.File
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.runCurrent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

@OptIn(ExperimentalCoroutinesApi::class)
class WriteViewModelTest {
    @get:Rule val temp = TemporaryFolder()

    @Test
    fun restoredIncompleteDraftClosesAfterElapsedSilenceLikeIos() = runTest {
        val stores = stores()
        val start = 1_770_000_000_000
        stores.draft.save("$start h\n471000 e")

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
        assertEquals("$start h\n471000 e\n8000", saved.text)
        assertEquals(479000, saved.durationMs)
        assertEquals(false, saved.isComplete)
        assertEquals(saved.text, stores.draft.load())
        assertEquals(saved.hash, stores.index.load().single().hash)
    }

    @Test
    fun restoredClosedDraftResetsWriteStateLikeIos() = runTest {
        val stores = stores()
        val start = 1_770_000_000_000
        stores.draft.save("$start h\n472000 e\n8000")

        val viewModel = WriteViewModel(
            activeDraftStore = stores.draft,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            nowMs = { start + 480000 },
            dispatcher = StandardTestDispatcher(testScheduler),
        )
        advanceUntilIdle()

        assertEquals("$start h\n472000 e\n8000", stores.archive.list().single().text)
        assertEquals("$start h\n472000 e\n8000", stores.draft.load())
        assertEquals("", viewModel.state.value.displayedText)
        assertEquals(0, viewModel.state.value.acceptedGlyphCount)
        assertEquals(0, viewModel.state.value.elapsedMs)
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
    fun shortSessionTerminalSilenceResetsWriteStateLikeIos() = runTest {
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
        now += 8_000
        advanceUntilIdle()

        val saved = stores.archive.list().single()
        assertEquals("1770000000000 h\n8000", saved.text)
        assertEquals(saved.text, stores.draft.load())
        assertEquals(saved.hash, viewModel.state.value.completedHash)
        assertEquals("", viewModel.state.value.displayedText)
        assertEquals(0, viewModel.state.value.acceptedGlyphCount)
        assertEquals(0, viewModel.state.value.elapsedMs)
    }

    @Test
    fun staleUtcDayDraftIsClearedOnLaunch() = runTest {
        val stores = stores()
        stores.draft.save("1770000000000 h")

        val viewModel = WriteViewModel(
            activeDraftStore = stores.draft,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            nowMs = { 1_770_086_400_000 },
            dispatcher = StandardTestDispatcher(testScheduler),
        )

        assertNull(stores.draft.load())
        assertEquals("", viewModel.state.value.displayedText)
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
        val dispatcher = StandardTestDispatcher(testScheduler)
        val viewModel = WriteViewModel(
            activeDraftStore = stores.draft,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            nowMs = { start },
            dispatcher = dispatcher,
        )

        viewModel.acceptGlyph("h")
        viewModel.ignoreBackspaceOrReplacement()
        viewModel.acceptGlyph("paste")

        assertEquals("$start h", stores.draft.load())
        assertEquals(1, stores.archive.list().size)
        assertEquals("that doesn't work here. just keep writing without agenda.", viewModel.state.value.errorMessage)

        advanceTimeBy(6_999)
        assertEquals("that doesn't work here. just keep writing without agenda.", viewModel.state.value.errorMessage)

        advanceTimeBy(1)
        runCurrent()
        assertNull(viewModel.state.value.errorMessage)
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

    @Test
    fun ankyNudgeShowsListeningThenOneLineAndClears() = runTest {
        val stores = stores()
        val dispatcher = StandardTestDispatcher(testScheduler)
        var now = 1_770_000_000_000
        var capturedText: String? = null
        var capturedIntent: MirrorIntent? = null
        val viewModel = WriteViewModel(
            activeDraftStore = stores.draft,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            identityProvider = { identity() },
            nowMs = { now },
            dispatcher = dispatcher,
            nudgeDispatcher = dispatcher,
            nudgeRequester = { bytes, _, _, intent ->
                capturedText = bytes.toString(Charsets.UTF_8)
                capturedIntent = intent
                MirrorResponsePayload(
                    hash = AnkyHasher.sha256Hex(bytes),
                    title = "Small Nudge",
                    reflection = "# Stay here\n\nsecond line should not show",
                    creditsRemaining = null,
                )
            },
        )

        viewModel.acceptGlyph("h")
        now += 120

        assertEquals(true, viewModel.startAnkyNudgeIfPossible())
        assertEquals("anky is listening to this .anky for one line.", viewModel.state.value.nudgeDialogueMessage)
        assertEquals(true, viewModel.state.value.isRequestingNudge)

        runCurrent()

        assertEquals("1770000000000 h", capturedText)
        assertEquals(MirrorIntent.Nudge, capturedIntent)
        assertEquals("Stay here", viewModel.state.value.nudgeDialogueMessage)
        assertEquals(false, viewModel.state.value.isRequestingNudge)

        advanceTimeBy(5_999)
        assertEquals("Stay here", viewModel.state.value.nudgeDialogueMessage)

        advanceTimeBy(1)
        runCurrent()
        assertEquals(false, viewModel.state.value.shouldShowNudgeDialogue)
    }

    @Test
    fun ankyNudgeIsUnavailableBeforeWritingStarts() = runTest {
        val stores = stores()
        val viewModel = WriteViewModel(
            activeDraftStore = stores.draft,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            identityProvider = { identity() },
            dispatcher = StandardTestDispatcher(testScheduler),
            nudgeDispatcher = StandardTestDispatcher(testScheduler),
            nudgeRequester = { _, _, _, _ -> error("Nudge should not request the mirror before writing starts.") },
        )

        assertEquals(false, viewModel.startAnkyNudgeIfPossible())
        assertEquals(false, viewModel.state.value.shouldShowNudgeDialogue)
    }

    private fun TestScope.stores(): Stores {
        val root = temp.newFolder()
        val ankys = File(root, "ankys")
        return Stores(
            draft = ActiveDraftStore.forDirectory(ankys),
            archive = LocalAnkyArchive.forDirectory(ankys),
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

    private fun identity(): WriterIdentity =
        WriterIdentity.fromRecoveryPhrase(
            RecoveryPhrase.parse(
                "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
            ),
        )
}
