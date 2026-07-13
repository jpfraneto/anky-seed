package inc.anky.android.write

import inc.anky.android.core.copy.AnkyCopyRegistry
import inc.anky.android.core.gate.UnlockGrant
import inc.anky.android.core.gate.UnlockTier
import inc.anky.android.core.gate.WriteBeforeScrollEventLogStore
import inc.anky.android.core.gate.WriteBeforeScrollEventName
import inc.anky.android.core.gate.QuickPassStore
import inc.anky.android.core.gate.UnlockStateStore
import inc.anky.android.core.identity.RecoveryPhrase
import inc.anky.android.core.identity.WriterIdentity
import inc.anky.android.core.mirror.MirrorResponsePayload
import inc.anky.android.core.protocol.AnkyHasher
import inc.anky.android.core.storage.ActiveDraftStore
import inc.anky.android.core.storage.LocalAnkyArchive
import inc.anky.android.core.storage.ReflectionStore
import inc.anky.android.core.storage.SessionIndexStore
import inc.anky.android.core.storage.WritingPreferences
import inc.anky.android.core.storage.WritingPreferencesStore
import inc.anky.android.feature.write.GateSession
import inc.anky.android.feature.write.RejectedWritingInput
import inc.anky.android.feature.write.WriteViewModel
import inc.anky.android.gate.FakeSharedPreferences
import java.io.File
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * WS7: preferences-driven input, WritingInputStats, the unlock ladder, and
 * the sealing flow — asserted against the iOS WriteViewModel + AppRoot
 * PostSessionSealingView behavior.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class WriteSealingAndLadderTest {
    @get:Rule val temp = TemporaryFolder()

    // Test sections are appended below.

    @Test
    fun allowedBackspaceRewritesTheSuffixThroughReplaceSuffixAndNeverEmpties() = runTest {
        val stores = stores()
        val start = 1_770_000_000_000
        var now = start
        val preferences = MutablePreferences()
        preferences.store.save(WritingPreferences.RitualDefault.copy(backspaceAllowed = true))
        val viewModel = makeViewModel(stores, nowMs = { now }, preferences = preferences)

        viewModel.acceptGlyph("h")
        now += 1_000
        viewModel.acceptGlyph("i")
        now += 500
        viewModel.requestBackspace()

        // Keep N-1 glyphs and re-type the last: the protocol only moves
        // forward, the page shows "h", nothing was rejected.
        assertEquals("h", viewModel.state.value.displayedText)
        assertEquals("$start h", stores.draft.load())
        assertEquals(0, viewModel.state.value.rejectedBackspaceCount)
        assertNull(viewModel.state.value.rejectedInputMessage)

        // A deletion that would empty the page is refused with the registry line.
        viewModel.requestBackspace()
        assertEquals("h", viewModel.state.value.displayedText)
        assertEquals(AnkyCopyRegistry.backspaceMessage, viewModel.state.value.rejectedInputMessage)
        assertEquals(1, viewModel.state.value.rejectedBackspaceCount)
    }

    @Test
    fun gateOriginatedSentenceAppliesQuickPassPassivelyWithNoButton() = runTest {
        val stores = stores()
        val gatePrefs = FakeSharedPreferences()
        var now = 1_770_000_000_000
        val appliedGrants = mutableListOf<UnlockGrant>()
        val viewModel = makeViewModel(
            stores,
            nowMs = { now },
            gate = GateSession(gatePrefs),
            onApplyUnlock = { appliedGrants.add(it) },
        )
        viewModel.markGateOriginatedSession(appDisplayName = "Instagram")

        "I am here.".forEach { glyph ->
            viewModel.acceptGlyph(glyph.toString())
            now += 400
        }

        // §5.4: no button, no stillness — pass spent, window open, line shown.
        assertEquals(UnlockTier.Quick, appliedGrants.single().tier)
        assertEquals(2, QuickPassStore(gatePrefs).remainingPasses(java.time.Instant.ofEpochMilli(now)))
        assertEquals(true, UnlockStateStore(gatePrefs).load().isUnlocked(java.time.Instant.ofEpochMilli(now)))
        assertEquals(
            AnkyCopyRegistry.quickPassUnlockLine("Instagram"),
            viewModel.state.value.quickPassUnlockLine,
        )
        assertEquals(true, viewModel.state.value.hasAppliedPassiveQuickUnlock)
        val names = eventNames(gatePrefs)
        assertTrue(names.contains(WriteBeforeScrollEventName.WritingStarted))
        assertTrue(names.contains(WriteBeforeScrollEventName.SentenceUnlockAvailable))
        assertTrue(names.contains(WriteBeforeScrollEventName.QuickPassUsed))

        // Left in motion after the passive unlock: seal immediately.
        viewModel.sealIfLeftInMotion()
        assertNotNull(viewModel.state.value.sealedSession)
        assertTrue(eventNames(gatePrefs).contains(WriteBeforeScrollEventName.WbsSessionSealed))
    }

    @Test
    fun organicSentenceNeverSurfacesOrSpendsAQuickPass() = runTest {
        val stores = stores()
        val gatePrefs = FakeSharedPreferences()
        var now = 1_770_000_000_000
        val appliedGrants = mutableListOf<UnlockGrant>()
        val viewModel = makeViewModel(
            stores,
            nowMs = { now },
            gate = GateSession(gatePrefs),
            onApplyUnlock = { appliedGrants.add(it) },
        )

        "I am here.".forEach { glyph ->
            viewModel.acceptGlyph(glyph.toString())
            now += 400
        }

        assertEquals(emptyList<UnlockGrant>(), appliedGrants)
        assertEquals(3, QuickPassStore(gatePrefs).remainingPasses(java.time.Instant.ofEpochMilli(now)))
        assertNull(viewModel.state.value.quickPassUnlockLine)
        assertNull(viewModel.state.value.availableUnlockGrant)

        // Daily sessions end in stillness: no quick unlock, no motion-seal.
        viewModel.sealIfLeftInMotion()
        assertNull(viewModel.state.value.sealedSession)
    }

    @Test
    fun crossingTheDailyTargetOffersTheDailyUnlockAndLogsSealAndOvershoot() = runTest {
        val stores = stores()
        val gatePrefs = FakeSharedPreferences()
        val start = 1_770_000_000_000
        var now = start
        var credited: Triple<String, Long, Long>? = null
        val viewModel = makeViewModel(
            stores,
            nowMs = { now },
            gate = GateSession(gatePrefs),
            onSealedComplete = { hash, durationMs, _, sealedAtMs ->
                credited = Triple(hash, durationMs, sealedAtMs)
            },
        )

        viewModel.acceptGlyph("h")
        now += 480_001 // past the 8-minute default target
        viewModel.acceptGlyph("h")

        val names = eventNames(gatePrefs)
        assertTrue(names.contains(WriteBeforeScrollEventName.DailyTargetReached))
        assertEquals(UnlockTier.Daily, viewModel.state.value.availableUnlockGrant?.tier)

        now += 8_000
        advanceUntilIdle()

        val sealed = viewModel.state.value.sealedSession
        val saved = stores.archive.list().single()
        assertEquals(UnlockTier.Daily, sealed?.unlockGrant?.tier)
        assertEquals(false, sealed?.showsFreeTargetMoment)
        assertEquals(saved.hash, credited?.first)
        assertEquals(saved.durationMs, credited?.second)
        val sealedNames = eventNames(gatePrefs)
        assertTrue(sealedNames.contains(WriteBeforeScrollEventName.WbsSessionSealed))
        assertTrue(sealedNames.contains(WriteBeforeScrollEventName.SessionOvershoot))
        assertNotNull(UnlockStateStore(gatePrefs).load().lastWroteAt)
    }

    @Test
    fun freeWriterTargetCrossingHoldsTheMomentScreenOncePerDay() = runTest {
        val stores = stores()
        val gatePrefs = FakeSharedPreferences()
        val start = 1_770_000_000_000
        var now = start
        val viewModel = makeViewModel(
            stores,
            nowMs = { now },
            gate = GateSession(gatePrefs),
            entitled = { false },
        )

        viewModel.acceptGlyph("h")
        now += 480_000
        viewModel.acceptGlyph("h") // one word, no sentence: no quick grant
        now += 8_000
        advanceUntilIdle()

        val sealed = viewModel.state.value.sealedSession
        assertEquals(true, sealed?.showsFreeTargetMoment)
        assertNull(sealed?.unlockGrant)
        viewModel.markFreeTargetMomentPresented()
        viewModel.finishSealing()

        // Same day, second crossing: the moment shows at most once per day.
        viewModel.acceptGlyph("h")
        now += 480_000
        viewModel.acceptGlyph("h")
        now += 8_000
        advanceUntilIdle()
        assertEquals(false, viewModel.state.value.sealedSession?.showsFreeTargetMoment)
    }

    @Test
    fun stayAfterSealingContinuesTheSealedPageInPlace() = runTest {
        val stores = stores()
        var now = 1_770_000_000_000
        val viewModel = makeViewModel(stores, nowMs = { now })

        viewModel.acceptGlyph("h")
        now += 1_000
        viewModel.acceptGlyph("i")
        now += 8_000
        advanceUntilIdle()
        assertNotNull(viewModel.state.value.sealedSession)
        assertEquals("", viewModel.state.value.displayedText)

        assertEquals(true, viewModel.stayAfterSealing())

        assertNull(viewModel.state.value.sealedSession)
        assertEquals("hi", viewModel.state.value.displayedText)
        assertEquals(true, viewModel.state.value.isFrozenForContinuation)
    }

    @Test
    fun entitledSealStreamsTheReflectionDedupesTheOpeningAndPersistsIt() = runTest {
        val stores = stores()
        var now = 1_770_000_000_000
        val opening = "The thread you followed tonight is the one you have been avoiding all week."
        val viewModel = makeViewModel(
            stores,
            nowMs = { now },
            reflectionRequester = { bytes, _, _, onChunk ->
                onChunk(opening)
                onChunk(opening)
                MirrorResponsePayload(
                    hash = AnkyHasher.sha256Hex(bytes),
                    title = "The Thread",
                    reflection = opening + opening,
                    creditsRemaining = null,
                )
            },
        )

        viewModel.acceptGlyph("h")
        now += 8_000
        advanceUntilIdle()
        viewModel.beginSealedSessionReflection()
        runCurrent()
        advanceUntilIdle()

        val state = viewModel.state.value
        assertEquals(false, state.sealedReflectionVeiled)
        assertEquals(true, state.sealedReflectionResolved)
        assertEquals(false, state.sealedReflectionFailed)
        // The repeated opening is shown once (iOS removingRepeatedOpening).
        assertEquals(opening, state.sealedReflectionMarkdown)
        val hash = state.sealedSession?.artifact?.hash
        assertEquals(opening + opening, stores.reflections.load(hash.orEmpty())?.reflection)
    }

    @Test
    fun freeSealNeverAsksTheMirrorAndStandsTheVeilInstead() = runTest {
        val stores = stores()
        var now = 1_770_000_000_000
        val viewModel = makeViewModel(
            stores,
            nowMs = { now },
            entitled = { false },
            reflectionRequester = { _, _, _, _ -> error("Free sessions make zero LLM calls.") },
        )

        viewModel.acceptGlyph("h")
        now += 8_000
        advanceUntilIdle()
        viewModel.beginSealedSessionReflection()
        advanceUntilIdle()

        val state = viewModel.state.value
        assertEquals(true, state.sealedReflectionVeiled)
        assertEquals(true, state.sealedReflectionResolved)
        assertEquals("", state.sealedReflectionMarkdown)
    }

    @Test
    fun freeWriterNudgeIsLocalAndThemedWithoutTouchingTheMirror() = runTest {
        val stores = stores()
        var now = 1_770_000_000_000
        val viewModel = makeViewModel(stores, nowMs = { now }, entitled = { false })

        viewModel.acceptGlyph("h")
        now += 1_000
        viewModel.acceptGlyph("i")

        assertEquals(true, viewModel.startAnkyNudgeIfPossible())
        val message = viewModel.state.value.nudgeDialogueMessage
        // < 240 seconds written routes to the "early" theme (EN).
        assertTrue(
            message == "You're just getting started. The thread is forming." ||
                message == "Give it a few more minutes. The real material is still coming." ||
                message == "I'm here. The first words are always the hardest.",
        )
    }

    @Test
    fun repeatedOpeningsCollapseAndHashLineKeepsTheIosFormat() = runTest {
        val opening = "a".repeat(30) + " and then the rest"
        assertEquals(opening, WriteViewModel.removingRepeatedOpening(opening + opening))
        assertEquals("short stays short", WriteViewModel.removingRepeatedOpening("short stays short"))
        assertEquals(
            "Sealed · abcd...wxyz",
            inc.anky.android.feature.write.sealedHashLine("abcd0000000000000000wxyz"),
        )
    }

    @Test
    fun blockedBackspaceSpeaksTheRegistryLineAndCountsIntoInputStats() = runTest {
        val stores = stores()
        var now = 1_770_000_000_000
        val viewModel = makeViewModel(stores, nowMs = { now })

        viewModel.acceptGlyph("h")
        viewModel.requestBackspace()
        viewModel.requestBackspace()
        viewModel.nudgeInvalidInput(RejectedWritingInput.Enter)

        assertEquals(AnkyCopyRegistry.enterMessage, viewModel.state.value.rejectedInputMessage)
        assertEquals("h", viewModel.state.value.displayedText)
        assertEquals(2, viewModel.state.value.rejectedBackspaceCount)
        assertEquals(1, viewModel.state.value.rejectedEnterCount)

        now += 8_000
        advanceUntilIdle()

        // iOS seals WritingInputStats(backspaceCount: rejectedBackspaceCount,
        // enterCount: rejectedEnterCount) into the archive sidecar.
        val saved = stores.archive.list().single()
        assertEquals(2, saved.inputStats.backspaceCount)
        assertEquals(1, saved.inputStats.enterCount)
    }

    private fun TestScope.makeViewModel(
        stores: Stores,
        nowMs: () -> Long,
        preferences: MutablePreferences = MutablePreferences(),
        gate: GateSession? = null,
        entitled: () -> Boolean = { true },
        onSealedComplete: (String, Long, Long?, Long) -> Unit = { _, _, _, _ -> },
        onUnlockAvailable: (UnlockGrant) -> Unit = {},
        onApplyUnlock: (UnlockGrant) -> Unit = {},
        reflectionRequester: (ByteArray, WriterIdentity, String, (String) -> Unit) -> MirrorResponsePayload =
            { _, _, _, _ -> error("No sealed reflection expected.") },
        dispatcher: CoroutineDispatcher = StandardTestDispatcher(testScheduler),
    ): WriteViewModel = WriteViewModel(
        activeDraftStore = stores.draft,
        archive = stores.archive,
        reflectionStore = stores.reflections,
        indexStore = stores.index,
        identityProvider = { identity() },
        nowMs = nowMs,
        dispatcher = dispatcher,
        nudgeDispatcher = dispatcher,
        nudgeRequester = { _, _, _, _ -> error("No mirror nudge expected.") },
        writingPreferencesStore = preferences.store,
        gateSession = gate,
        entitledForGating = entitled,
        onSealedComplete = onSealedComplete,
        onUnlockAvailable = onUnlockAvailable,
        onApplyUnlock = onApplyUnlock,
        reflectionRequester = reflectionRequester,
    )

    private class MutablePreferences {
        var stored: String? = null
        val store = WritingPreferencesStore.forStorage(read = { stored }, write = { stored = it })
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

    private fun eventNames(prefs: FakeSharedPreferences): List<WriteBeforeScrollEventName> =
        WriteBeforeScrollEventLogStore(prefs).load().map { it.name }
}
