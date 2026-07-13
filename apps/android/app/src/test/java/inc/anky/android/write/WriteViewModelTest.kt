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
import inc.anky.android.core.copy.AnkyCopyRegistry
import inc.anky.android.feature.write.RejectedWritingInput
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

        val viewModel = WriteViewModel(
            activeDraftStore = stores.draft,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            nowMs = { start + 472000 + 8000 },
            dispatcher = StandardTestDispatcher(testScheduler),
        )
        advanceUntilIdle()

        val saved = stores.archive.list().single()
        assertEquals("$start h\n471000 e", saved.text)
        assertEquals(471000, saved.durationMs)
        assertEquals(false, saved.isComplete)
        assertEquals("$start h\n471000 e", stores.draft.load())
        assertEquals(saved.hash, viewModel.state.value.sealedSession?.artifact?.hash)
        assertNull(viewModel.state.value.completedHash)
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
    fun sealedSessionIsHeldForSealingFlowAndFinishSealingClearsIt() = runTest {
        val stores = stores()
        val start = 1_770_000_000_000
        stores.draft.save("$start h\n480000 e")
        val viewModel = WriteViewModel(
            activeDraftStore = stores.draft,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            nowMs = { start + 480000 + 8000 },
            dispatcher = StandardTestDispatcher(testScheduler),
        )
        advanceUntilIdle()

        // The seal no longer routes straight to Reveal: it holds the sealed
        // session for PostSessionSealingScreen (iOS PostSessionSealingView).
        val sealed = viewModel.state.value.sealedSession
        assertEquals(stores.archive.list().single().hash, sealed?.artifact?.hash)
        assertNull(viewModel.state.value.completedHash)
        assertNull(sealed?.unlockGrant)
        assertEquals(false, sealed?.showsFreeTargetMoment)

        viewModel.finishSealing()

        assertNull(viewModel.state.value.sealedSession)
        assertNull(viewModel.state.value.completedHash)
    }

    @Test
    fun todayAnkyCountCountsCompleteUtcSessionsLikeIosLaunchPrompt() = runTest {
        val stores = stores()
        val start = 1_770_000_000_000
        val complete = stores.archive.save("$start h\n480000 e\n8000")
        val fragment = stores.archive.save("${start + 20_000} h\n1000 e\n8000")
        stores.index.upsert(inc.anky.android.core.storage.SessionSummary.make(complete, null))
        stores.index.upsert(inc.anky.android.core.storage.SessionSummary.make(fragment, null))

        val viewModel = WriteViewModel(
            activeDraftStore = stores.draft,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            nowMs = { start + 60_000 },
            dispatcher = StandardTestDispatcher(testScheduler),
        )

        assertEquals(1, viewModel.state.value.todayAnkyCount)
    }

    @Test
    fun completedSessionNavigatesAndClearsDraftLikeIos() = runTest {
        val stores = stores()
        val start = 1_770_000_000_000
        stores.draft.save("$start h\n480000 e")
        val viewModel = WriteViewModel(
            activeDraftStore = stores.draft,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            nowMs = { start + 480000 + 8000 },
            dispatcher = StandardTestDispatcher(testScheduler),
        )
        advanceUntilIdle()

        val sealedHash = viewModel.state.value.sealedSession?.artifact?.hash
        val saved = stores.archive.list().single()

        assertEquals("$start h\n480000 e", saved.text)
        assertEquals(AnkyHasher.sha256Hex("$start h\n480000 e".toByteArray(Charsets.UTF_8)), saved.hash)
        assertEquals(saved.hash, sealedHash)
        assertEquals("", viewModel.state.value.displayedText)
        assertEquals("", viewModel.state.value.latestGlyph)
        assertEquals(0, viewModel.state.value.acceptedGlyphCount)
        assertEquals(480000, viewModel.state.value.elapsedMs)
        assertEquals(8000, viewModel.state.value.silenceElapsedMs)
        assertEquals(0, viewModel.state.value.silenceRemainingMs)
        assertEquals(1f, viewModel.state.value.progress)
        assertNull(stores.draft.load())
    }

    @Test
    fun saveFailureShowsIosErrorCopyAndPreservesClosedDraft() = runTest {
        val root = temp.newFolder()
        val archiveFile = temp.newFile("archive-is-not-a-directory")
        val draft = ActiveDraftStore.forDirectory(File(root, "draft"))
        val reflections = ReflectionStore.forDirectory(File(root, "reflections"))
        val index = SessionIndexStore.forFile(File(root, "session-index.json"))
        val start = 1_770_000_000_000
        draft.save("$start h\n480000 e")

        val viewModel = WriteViewModel(
            activeDraftStore = draft,
            archive = LocalAnkyArchive.forDirectory(archiveFile),
            reflectionStore = reflections,
            indexStore = index,
            nowMs = { start + 480000 + 8000 },
            dispatcher = StandardTestDispatcher(testScheduler),
        )
        advanceUntilIdle()

        assertEquals("Could not save this .anky.", viewModel.state.value.errorMessage)
        assertEquals("$start h\n480000 e", draft.load())
        assertEquals(0, index.load().size)
    }

    @Test
    fun shortSessionSilenceCloseRoutesIntoSealingFlow() = runTest {
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
        assertEquals("1770000000000 h", saved.text)
        assertEquals("1770000000000 h", stores.draft.load())
        assertEquals(saved.hash, viewModel.state.value.sealedSession?.artifact?.hash)
        assertNull(viewModel.state.value.completedHash)
        assertEquals("", viewModel.state.value.displayedText)
        assertEquals(0, viewModel.state.value.acceptedGlyphCount)
        assertEquals(0, viewModel.state.value.elapsedMs)
        assertEquals(8000, viewModel.state.value.silenceElapsedMs)
        assertEquals(0, viewModel.state.value.silenceRemainingMs)
        assertEquals(0f, viewModel.state.value.progress)
    }

    @Test
    fun shortSessionSilenceCloseDoesNotRemainFrozenInWrite() = runTest {
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

        viewModel.refreshLiveState()

        assertEquals(saved.hash, viewModel.state.value.sealedSession?.artifact?.hash)
        assertEquals(false, viewModel.state.value.isClosing)
        assertEquals("", viewModel.state.value.displayedText)
        assertEquals(0, viewModel.state.value.acceptedGlyphCount)
        assertEquals("1770000000000 h", stores.draft.load())
    }

    @Test
    fun incompleteSavePreservesDraftAndStillEntersSealingFlow() = runTest {
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
        now += 1_000
        viewModel.acceptGlyph("i")
        now += 8_000
        advanceTimeBy(8_000)
        runCurrent()

        val saved = stores.archive.list().single()
        assertEquals("1770000000000 h\n1000 i", stores.draft.load())
        assertEquals(saved.hash, viewModel.state.value.sealedSession?.artifact?.hash)
        assertEquals(saved.hash, stores.index.load().single().hash)
    }

    @Test
    fun incompleteSaveDoesNotAutoContinue() = runTest {
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
        val sealedFragment = stores.archive.list().single()
        // Leaving the sealing flow lands on a fresh page — the sealed
        // fragment is never silently resumed (iOS finishSealingToMainScreen).
        viewModel.finishSealing()

        now += 1_000
        viewModel.acceptGlyph("!")

        assertEquals("${now} !", stores.draft.load())
        assertEquals(true, stores.archive.fileList().any { it.name == "${sealedFragment.hash}.anky" })
        assertEquals(false, stores.archive.list().any { it.text == "1770000000000 h\n0 !" })
        assertEquals(true, viewModel.state.value.isClosing)
        assertEquals("!", viewModel.state.value.displayedText)
        assertEquals(1, viewModel.state.value.acceptedGlyphCount)
    }

    @Test
    fun nonTerminalFragmentContinuesInWriteAndReplacesOldFragment() = runTest {
        val stores = stores()
        val start = 1_770_000_000_000
        val oldFragment = stores.archive.save("$start h\n1000 i")
        stores.index.upsert(inc.anky.android.core.storage.SessionSummary.make(oldFragment, null))
        var now = start + 120_000
        val dispatcher = StandardTestDispatcher(testScheduler)
        val viewModel = WriteViewModel(
            activeDraftStore = stores.draft,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            nowMs = { now },
            dispatcher = dispatcher,
        )

        assertEquals(true, viewModel.continueSession(oldFragment))

        assertEquals("hi", viewModel.state.value.displayedText)
        assertEquals(2, viewModel.state.value.acceptedGlyphCount)
        assertEquals(1000, viewModel.state.value.elapsedMs)
        assertEquals(0, viewModel.state.value.silenceElapsedMs)
        assertEquals(false, viewModel.state.value.isClosing)
        assertEquals("$start h\n1000 i", stores.draft.load())

        viewModel.acceptGlyph("!")
        now += 8_000
        advanceTimeBy(8_000)
        runCurrent()

        val continued = stores.archive.list().single()
        assertEquals("$start h\n1000 i\n0 !", continued.text)
        assertEquals("hi!", continued.reconstructedText)
        assertEquals(listOf(continued.hash), stores.index.load().map { it.hash })
        assertEquals(false, stores.archive.fileList().any { it.name == "${oldFragment.hash}.anky" })
        assertEquals("$start h\n1000 i\n0 !", stores.draft.load())
    }

    @Test
    fun continuedSessionProgressUsesProtocolDurationNotPausedWallClock() = runTest {
        val stores = stores()
        val start = 1_770_000_000_000
        val oldFragment = stores.archive.save("$start h\n457000 i")
        stores.index.upsert(inc.anky.android.core.storage.SessionSummary.make(oldFragment, null))
        var now = start + 900_000
        val viewModel = WriteViewModel(
            activeDraftStore = stores.draft,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            nowMs = { now },
            dispatcher = StandardTestDispatcher(testScheduler),
        )

        assertEquals(true, viewModel.continueSession(oldFragment))
        assertEquals(457000, viewModel.state.value.elapsedMs)
        assertEquals(false, viewModel.state.value.hasReachedRitualMark)

        viewModel.acceptGlyph("!")
        now += 22_000
        viewModel.refreshLiveState()

        assertEquals(457000, viewModel.state.value.elapsedMs)
        assertEquals(false, viewModel.state.value.hasReachedRitualMark)

        viewModel.acceptGlyph("?")
        assertEquals(479000, viewModel.state.value.elapsedMs)
        assertEquals(false, viewModel.state.value.hasReachedRitualMark)

        now += 1_000
        viewModel.acceptGlyph(".")

        assertEquals(480000, viewModel.state.value.elapsedMs)
        assertEquals(true, viewModel.state.value.hasReachedRitualMark)
    }

    @Test
    fun terminalMarkedFragmentIsNotMadeContinuableByStrippingTerminalSilence() = runTest {
        val stores = stores()
        val start = 1_770_000_000_000
        val closedFragment = stores.archive.save("$start h\n1000 i\n8000")
        stores.index.upsert(inc.anky.android.core.storage.SessionSummary.make(closedFragment, null))
        val viewModel = WriteViewModel(
            activeDraftStore = stores.draft,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            nowMs = { start + 120_000 },
            dispatcher = StandardTestDispatcher(testScheduler),
        )

        assertEquals(false, viewModel.continueSession(closedFragment))

        assertEquals("", viewModel.state.value.displayedText)
        assertNull(stores.draft.load())
        assertEquals(listOf(closedFragment.hash), stores.index.load().map { it.hash })
        assertEquals(listOf(closedFragment.hash), stores.archive.list().map { it.hash })
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
        viewModel.nudgeInvalidInput(RejectedWritingInput.Backspace)
        viewModel.acceptGlyph("paste")

        assertEquals("$start h", stores.draft.load())
        assertEquals(1, stores.archive.list().size)
        assertEquals(AnkyCopyRegistry.backspaceMessage, viewModel.state.value.rejectedInputMessage)
        assertEquals(1, viewModel.state.value.rejectedInputPulseId)
        assertEquals(1, viewModel.state.value.rejectedBackspaceCount)

        advanceTimeBy(1_999)
        assertEquals(AnkyCopyRegistry.backspaceMessage, viewModel.state.value.rejectedInputMessage)

        advanceTimeBy(1)
        runCurrent()
        assertNull(viewModel.state.value.rejectedInputMessage)
    }

    @Test
    fun recentWriteErrorCanBeReplayedFromAnkyTapLikeIos() = runTest {
        val stores = stores()
        val dispatcher = StandardTestDispatcher(testScheduler)
        val viewModel = WriteViewModel(
            activeDraftStore = stores.draft,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            dispatcher = dispatcher,
        )

        viewModel.nudgeInvalidInput(RejectedWritingInput.Enter)
        assertEquals(AnkyCopyRegistry.enterMessage, viewModel.state.value.rejectedInputMessage)
        assertEquals(1, viewModel.state.value.rejectedEnterCount)

        advanceTimeBy(2_000)
        runCurrent()
        assertNull(viewModel.state.value.rejectedInputMessage)

        assertEquals(true, viewModel.replayRecentPromptIfAvailable())
        assertEquals(AnkyCopyRegistry.enterMessage, viewModel.state.value.errorMessage)

        advanceTimeBy(2_000)
        runCurrent()
        assertNull(viewModel.state.value.errorMessage)

        advanceTimeBy(5_000)
        runCurrent()
        assertEquals(false, viewModel.replayRecentPromptIfAvailable())
    }

    @Test
    fun openWritingPortalRequestsFreshKeyboardFocusLikeIos() = runTest {
        val stores = stores()
        val viewModel = WriteViewModel(
            activeDraftStore = stores.draft,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            dispatcher = StandardTestDispatcher(testScheduler),
        )
        val initialFocusRequest = viewModel.state.value.keyboardFocusRequestId

        viewModel.openWritingPortal()

        assertEquals(initialFocusRequest + 1, viewModel.state.value.keyboardFocusRequestId)
    }

    @Test
    fun resetAfterAccountDeletionClearsActiveDraftAndTransientWriteState() = runTest {
        val stores = stores()
        val dispatcher = StandardTestDispatcher(testScheduler)
        var now = 1_770_000_000_000
        val viewModel = WriteViewModel(
            activeDraftStore = stores.draft,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            nowMs = { now },
            dispatcher = dispatcher,
        )

        viewModel.acceptGlyph("h")
        viewModel.nudgeInvalidInput(RejectedWritingInput.Backspace)

        assertEquals("$now h", stores.draft.load())
        assertEquals("h", viewModel.state.value.displayedText)
        assertEquals(1, viewModel.state.value.acceptedGlyphCount)
        assertEquals(AnkyCopyRegistry.backspaceMessage, viewModel.state.value.rejectedInputMessage)

        viewModel.resetAfterAccountDeletion()
        now += 8_000
        advanceTimeBy(8_000)
        runCurrent()

        assertNull(stores.draft.load())
        assertEquals(0, stores.archive.list().size)
        assertEquals("", viewModel.state.value.displayedText)
        assertEquals(0, viewModel.state.value.acceptedGlyphCount)
        assertEquals(false, viewModel.state.value.isClosing)
        assertNull(viewModel.state.value.completedHash)
        assertNull(viewModel.state.value.sealedSession)
        assertNull(viewModel.state.value.errorMessage)
        assertNull(viewModel.state.value.rejectedInputMessage)
        assertEquals(0, viewModel.state.value.rejectedBackspaceCount)
        assertEquals(false, viewModel.state.value.shouldShowNudgeDialogue)
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
    fun repeatedGlyphsAppendAsSeparateProtocolEvents() = runTest {
        val stores = stores()
        val now = 1_770_000_000_000
        val viewModel = WriteViewModel(
            activeDraftStore = stores.draft,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            nowMs = { now },
            dispatcher = StandardTestDispatcher(testScheduler),
        )

        viewModel.acceptGlyphs("literally app".map { it.toString() })

        val lines = stores.draft.load().orEmpty().lines()
        assertEquals("literally app", viewModel.state.value.displayedText)
        assertEquals(13, viewModel.state.value.acceptedGlyphCount)
        assertEquals("$now l", lines[0])
        assertEquals("0 l", lines[6])
        assertEquals("0 l", lines[7])
        assertEquals("0 SPACE", lines[9])
        assertEquals("0 p", lines[11])
        assertEquals("0 p", lines[12])
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
        viewModel.acceptGlyph(" ")

        assertEquals(true, viewModel.startAnkyNudgeIfPossible())
        assertEquals("anky is listening to this .anky for one line.", viewModel.state.value.nudgeDialogueMessage)
        assertEquals(true, viewModel.state.value.isRequestingNudge)

        runCurrent()

        assertEquals("1770000000000 h\n120 SPACE", capturedText)
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
