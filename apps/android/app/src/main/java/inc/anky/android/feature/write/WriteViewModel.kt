package inc.anky.android.feature.write

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import inc.anky.android.BuildConfig
import inc.anky.android.core.copy.AnkyCopyRegistry
import inc.anky.android.core.gate.GateWritingSnapshot
import inc.anky.android.core.gate.UnlockGrant
import inc.anky.android.core.gate.UnlockPolicy
import inc.anky.android.core.gate.UnlockTier
import inc.anky.android.core.gate.WriteBeforeScrollEventName
import inc.anky.android.core.gate.WriteBeforeScrollSessionMetricTracker
import inc.anky.android.core.gate.WriteBeforeScrollSessionMetrics
import inc.anky.android.core.gate.WriteBeforeScrollUnlockLadderAction
import inc.anky.android.core.identity.WriterIdentity
import inc.anky.android.core.mirror.MirrorClient
import inc.anky.android.core.mirror.MirrorClientError
import inc.anky.android.core.mirror.MirrorIntent
import inc.anky.android.core.mirror.MirrorResponsePayload
import inc.anky.android.core.protocol.AnkyDuration
import inc.anky.android.core.protocol.AnkyHasher
import inc.anky.android.core.protocol.AnkyParser
import inc.anky.android.core.protocol.AnkyReconstructor
import inc.anky.android.core.protocol.AnkyValidator
import inc.anky.android.core.protocol.AnkyValidation
import inc.anky.android.core.protocol.AnkyWriter
import inc.anky.android.core.storage.ActiveDraftStore
import inc.anky.android.core.storage.LocalAnkyArchive
import inc.anky.android.core.storage.LocalReflection
import inc.anky.android.core.storage.ReflectionStore
import inc.anky.android.core.storage.SavedAnky
import inc.anky.android.core.storage.SessionIndexStore
import inc.anky.android.core.storage.SessionSummary
import inc.anky.android.core.storage.WritingInputStats
import inc.anky.android.core.storage.WritingPreferences
import inc.anky.android.core.storage.WritingPreferencesStore
import java.time.Instant
import java.time.ZoneOffset
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** iOS `RejectedWritingInput` (WriteView.swift). */
enum class RejectedWritingInput {
    Backspace,
    Enter,
}

/**
 * Everything the sealing flow needs about the just-sealed session — the
 * Android shape of what iOS AppRoot holds in `sealingArtifact` /
 * `sealingUnlockGrant` / `sealingShowsFreeTargetMoment`.
 */
data class SealedWritingSession(
    val artifact: SavedAnky,
    val unlockGrant: UnlockGrant?,
    val isGateOriginated: Boolean,
    val gateOriginAppDisplayName: String?,
    val showsFreeTargetMoment: Boolean,
    val quickPassesRemaining: Int,
    val remainingToTargetMs: Long,
    val isFirstGate: Boolean,
)

data class WriteState(
    val latestGlyph: String = "",
    val displayedText: String = "",
    val displayedGlyphs: List<WritingGlyph> = emptyList(),
    val elapsedMs: Long = 0,
    val silenceElapsedMs: Long = 0,
    val silenceRemainingMs: Long = AnkyDuration.TerminalSilenceMs,
    val progress: Float = 0f,
    val isClosing: Boolean = false,
    val completedHash: String? = null,
    val acceptedGlyphCount: Int = 0,
    val todayAnkyCount: Int = 0,
    val keyboardFocusRequestId: Int = 0,
    val continuationScrollRequestId: Int = 0,
    val errorMessage: String? = null,
    val nudgeMessage: String? = null,
    val isRequestingNudge: Boolean = false,
    val isFrozenForContinuation: Boolean = false,
    val rejectedInputPulseId: Int = 0,
    // The talking top bar (iOS registry lines on every rejected key).
    val rejectedInputMessage: String? = null,
    val rejectedBackspaceCount: Int = 0,
    val rejectedEnterCount: Int = 0,
    // Preferences-driven input (iOS WritingPreferencesStore).
    val writingPreferences: WritingPreferences = WritingPreferences.RitualDefault,
    // Write Before You Scroll ladder surface.
    val sessionMetrics: WriteBeforeScrollSessionMetrics = WriteBeforeScrollSessionMetrics(),
    val availableUnlockGrant: UnlockGrant? = null,
    val quickPassesRemaining: Int = UnlockPolicy.QuickPassDailyAllowance,
    val quickPassUnlockLine: String? = null,
    val hasAppliedPassiveQuickUnlock: Boolean = false,
    val dailyTargetMs: Long = UnlockPolicy.DefaultDailyTargetMs,
    // The sealing flow (iOS PostSessionSealingView): set at seal, cleared by
    // finishSealing()/stayAfterSealing().
    val sealedSession: SealedWritingSession? = null,
    val sealedReflectionMarkdown: String = "",
    val sealedReflectionResolved: Boolean = false,
    val sealedReflectionFailed: Boolean = false,
    /** Phase-3 §3: free sessions never ask the mirror — the veil stands in. */
    val sealedReflectionVeiled: Boolean = false,
) {
    val hasReachedRitualMark: Boolean
        get() = elapsedMs >= AnkyDuration.CompleteRitualMs

    val shouldShowNudgeDialogue: Boolean
        get() = isRequestingNudge || !nudgeMessage.isNullOrBlank()

    val nudgeDialogueMessage: String
        get() = if (isRequestingNudge) {
            "anky is listening to this .anky for one line."
        } else {
            nudgeMessage.orEmpty()
        }
}

data class WritingGlyph(
    val glyph: String,
    val silenceProgress: Float,
)

class WriteViewModel(
    private val activeDraftStore: ActiveDraftStore,
    private val archive: LocalAnkyArchive,
    private val reflectionStore: ReflectionStore,
    private val indexStore: SessionIndexStore,
    private val identityProvider: () -> WriterIdentity = { error("Writer identity is not configured.") },
    private val mirrorClientProvider: () -> MirrorClient = { error("Mirror client is not configured.") },
    private val nowMs: () -> Long = { System.currentTimeMillis() },
    private val dispatcher: CoroutineDispatcher = Dispatchers.Main,
    private val nudgeDispatcher: CoroutineDispatcher = Dispatchers.IO,
    private val nudgeRequester: (ByteArray, WriterIdentity, String, MirrorIntent) -> MirrorResponsePayload = { bytes, identity, appVersion, intent ->
        mirrorClientProvider().askAnky(
            bytes = bytes,
            identity = identity,
            appVersion = appVersion,
            intent = intent,
        )
    },
    // --- WS7 additions, all defaulted so AnkyApp.kt call sites stay source-compatible ---
    private val writingPreferencesStore: WritingPreferencesStore =
        WritingPreferencesStore.forStorage(read = { null }, write = {}),
    private val gateSession: GateSession? = null,
    /**
     * Phase-3: the Daily Unlock, mirror nudges, and the sealing reflection
     * belong to the subscription. Wire `EntitlementStore.state` here (iOS
     * keeps `dailyUnlockEntitled` fresh from AppRoot).
     */
    private val entitledForGating: () -> Boolean = { true },
    /**
     * Level credit hook, called synchronously at seal before any UI
     * transition. The integrator wires
     * `LevelProgressStore.creditSealedSession(hash, durationMs,
     * replacedDurationMs, sealedAtMs)` + `LevelSyncClient.flushUnreported`
     * + glance sync (iOS WriteViewModel.sealAndSave).
     */
    private val onSealedComplete: (hash: String, durationMs: Long, replacedDurationMs: Long?, sealedAtMs: Long) -> Unit =
        { _, _, _, _ -> },
    /** iOS `bindWriteBeforeScrollUnlockAvailabilityHandler`. */
    private val onUnlockAvailable: (UnlockGrant) -> Unit = {},
    /**
     * iOS `bindWriteBeforeScrollPassiveUnlockHandler`: the grant is already
     * persisted (pass consumed / window opened) — this callback is for the
     * blocking runtime to clear the shield and schedule the relock.
     */
    private val onApplyUnlock: (UnlockGrant) -> Unit = {},
    /** The sealed-session reflection stream (entitled writers only). */
    private val reflectionRequester: (ByteArray, WriterIdentity, String, (String) -> Unit) -> MirrorResponsePayload =
        { bytes, identity, appVersion, onChunk ->
            mirrorClientProvider().askAnky(
                bytes = bytes,
                identity = identity,
                appVersion = appVersion,
                intent = MirrorIntent.Reflection,
                reflectionChunk = { event -> onChunk(event.chunk) },
            )
        },
) : ViewModel() {
    private val restoredDraftText = activeDraftForToday()
    private val restoredWriterResult = restoredDraftText?.let { runCatching { AnkyWriter.fromDraft(it) } }
    private val restoredWriter = restoredWriterResult?.getOrNull()
    private val restoreErrorMessage =
        if (restoredWriterResult?.isFailure == true) "Could not restore the active draft." else null
    private var writer: AnkyWriter =
        if (restoredWriter?.isClosed == true) AnkyWriter() else restoredWriter ?: AnkyWriter()
    private var closeJob: Job? = null
    private var sessionStartMs: Long? = restoredStartMs()
    private var displayedText: String = restoredDisplayedText()
    private var displayedGlyphs: List<WritingGlyph> = restoredDisplayedText().map { WritingGlyph(it.toString(), 1f) }
    private var acceptedGlyphCount = restoredGlyphCount()
    private var nudgeJob: Job? = null
    private var nudgeClearJob: Job? = null
    private var errorClearJob: Job? = null
    private var rejectedInputClearJob: Job? = null
    private var nudgeMessage: String? = null
    private var isRequestingNudge = false
    private var visibleErrorMessage: String? = restoreErrorMessage
    private var recentErrorMessage: String? = null
    private var keyboardFocusRequestId = 0
    private var continuationScrollRequestId = 0
    private var isFrozenForContinuation = false
    private var continuedArtifactToReplace: SavedAnky? = null
    private var rejectedInputPulseId = 0
    private var rejectedInputMessage: String? = null
    private var rejectedBackspaceCount = 0
    private var rejectedEnterCount = 0
    private var writingPreferences: WritingPreferences = writingPreferencesStore.load()
    private var lastLocalNudgeAtMs: Long? = null
    private var localNudgeOffset = 0
    // --- Write Before You Scroll session state (iOS WriteViewModel fields) ---
    private val sessionTracker = WriteBeforeScrollSessionMetricTracker()
    private var sessionMetrics = sessionTracker.metrics
    private var availableUnlockGrant: UnlockGrant? = null
    private var quickPassesRemaining = UnlockPolicy.QuickPassDailyAllowance
    private var quickPassUnlockLine: String? = null
    private var hasAppliedPassiveQuickUnlock = false
    private var hasAppliedPassiveDailyUnlockUpgrade = false
    private var freeTargetMomentPending = false
    private var dailyTargetMs: Long = UnlockPolicy.DefaultDailyTargetMs
    var isGateOriginatedSession = false
        private set
    var gateOriginAppDisplayName: String? = null
        private set
    // --- Sealing flow state ---
    private var sealedSession: SealedWritingSession? = null
    private var sealedReflectionMarkdown = ""
    private var sealedReflectionResolved = false
    private var sealedReflectionFailed = false
    private var sealedReflectionVeiled = false
    private var sealedReflectionStartedForHash: String? = null
    private var sealedReflectionStreamRaw = ""
    private var sealedReflectionJob: Job? = null

    private val _state = MutableStateFlow(deriveState())
    val state: StateFlow<WriteState> = _state
    val devSampleAnkyArtifact: String
        get() = DevAnkyFixture.validArtifact

    init {
        refreshGateBaselines(Instant.ofEpochMilli(nowMs()))
        scheduleCloseForRestoredDraft()
    }

    fun acceptGlyph(glyph: String) {
        val now = nowMs()
        acceptGlyphAt(glyph, now)
    }

    fun acceptGlyphs(glyphs: List<String>) {
        if (glyphs.isEmpty()) return
        val now = nowMs()
        if (isFrozenForContinuation) {
            glyphs.forEach { glyph -> acceptGlyphAt(glyph, now) }
            return
        }
        val previousAcceptedMs = writer.lastAcceptedMs
        if (previousAcceptedMs == null) {
            glyphs.forEach { glyph -> acceptGlyphAt(glyph, now) }
            return
        }

        val elapsedSinceLastGlyph = maxOf(0, now - previousAcceptedMs)
        glyphs.forEachIndexed { index, glyph ->
            val distributedElapsed = elapsedSinceLastGlyph * (index + 1) / glyphs.size
            acceptGlyphAt(glyph, previousAcceptedMs + distributedElapsed)
        }
    }

    private fun acceptGlyphAt(glyph: String, now: Long) {
        if (sealedSession != null) return
        resumeIfFrozen(now)
        freezeLatestGlyph(now)
        if (!writer.isStarted) sessionStartMs = now
        if (!writer.accept(glyph, now)) return
        displayedText += glyph
        displayedGlyphs = displayedGlyphs + WritingGlyph(glyph, 0f)
        acceptedGlyphCount += 1
        activeDraftStore.save(writer.text)
        recordWriteBeforeScrollProgress(acceptedCharacterCount = 1, epochMs = now)
        scheduleClose(afterMs = AnkyDuration.TerminalSilenceMs)
        _state.value = deriveState(latestGlyph = glyph)
    }

    /**
     * A backspace, in the iOS shape: rejected with the registry line when the
     * preference is off (or the page would go empty), otherwise recorded as a
     * forward suffix rewrite via `AnkyWriter.replaceSuffix` — keep everything
     * but the new final glyph, then re-type that glyph. The text can never go
     * empty through here (iOS WriteView `endDeletion`).
     */
    fun requestBackspace() {
        if (sealedSession != null) return
        if (!writingPreferences.backspaceAllowed) {
            nudgeInvalidInput(RejectedWritingInput.Backspace)
            return
        }
        if (displayedGlyphs.size < 2 || writer.isClosed) {
            nudgeInvalidInput(RejectedWritingInput.Backspace)
            return
        }
        val now = nowMs()
        resumeIfFrozen(now)
        freezeLatestGlyph(now)
        val proposed = displayedGlyphs.dropLast(1)
        val prefixGlyphCount = proposed.size - 1
        val tailGlyph = proposed.last().glyph
        val accepted = writer.replaceSuffix(
            keepingPrefixGlyphCount = prefixGlyphCount,
            replacementText = tailGlyph,
            epochMs = now,
        )
        if (accepted.isEmpty()) {
            nudgeInvalidInput(RejectedWritingInput.Backspace)
            return
        }
        displayedGlyphs = proposed.take(prefixGlyphCount) +
            accepted.map { WritingGlyph(it, 0f) }
        displayedText = displayedGlyphs.joinToString(separator = "") { it.glyph }
        acceptedGlyphCount = displayedGlyphs.size
        activeDraftStore.save(writer.text)
        recordWriteBeforeScrollProgress(acceptedCharacterCount = accepted.size, epochMs = now)
        scheduleClose(afterMs = AnkyDuration.TerminalSilenceMs)
        _state.value = deriveState(latestGlyph = accepted.last())
    }

    /**
     * The top bar is the interface's voice: it speaks on every rejected key,
     * quietly, in the registry's words (iOS `nudgeInvalidInput`).
     */
    fun nudgeInvalidInput(input: RejectedWritingInput) {
        rejectedInputPulseId += 1
        when (input) {
            RejectedWritingInput.Backspace -> {
                rejectedBackspaceCount += 1
                showRejectedInputLine(AnkyCopyRegistry.backspaceMessage)
            }
            RejectedWritingInput.Enter -> {
                rejectedEnterCount += 1
                showRejectedInputLine(AnkyCopyRegistry.enterMessage)
            }
        }
    }

    fun startAnkyNudgeIfPossible(): Boolean {
        if (!writer.isStarted || writer.text.isBlank()) return false
        if (_state.value.shouldShowNudgeDialogue) return true

        // Phase-3: server nudges are LLM calls and belong to the subscription.
        // Free sessions get the local themed line — the writing is still met,
        // just not by the mirror (iOS WriteViewModel.requestAnkyNudge guard).
        if (!entitledForGating()) {
            showContextualNudge()
            return true
        }

        isRequestingNudge = true
        nudgeMessage = null
        val nudgeText = writer.text
        _state.value = deriveState(latestGlyph = _state.value.latestGlyph)

        nudgeJob?.cancel()
        nudgeJob = viewModelScope.launch(nudgeDispatcher) {
            requestAnkyNudge(nudgeText)
        }
        return true
    }

    fun replayRecentPromptIfAvailable(): Boolean {
        if (writer.isStarted && writer.text.isNotBlank()) {
            return startAnkyNudgeIfPossible()
        }
        val message = recentErrorMessage?.takeIf { it.isNotBlank() } ?: return false
        if (visibleErrorMessage != null) return true

        visibleErrorMessage = message
        _state.value = deriveState(latestGlyph = _state.value.latestGlyph)
        scheduleErrorFade(message, keepRecall = false)
        return true
    }

    fun openWritingPortal() {
        writingPreferences = writingPreferencesStore.load()
        refreshGateBaselines(Instant.ofEpochMilli(nowMs()))
        refreshUnlockOffer(Instant.ofEpochMilli(nowMs()))
        keyboardFocusRequestId += 1
        _state.value = deriveState(latestGlyph = _state.value.latestGlyph)
    }

    /**
     * Marks this session as opened from the gate (the writer was trying to
     * reach a blocked app). Enables the contextual unlock line and the
     * "go back to {app}" seal button.
     */
    fun markGateOriginatedSession(appDisplayName: String?) {
        isGateOriginatedSession = true
        gateOriginAppDisplayName = appDisplayName
        _state.value = deriveState(latestGlyph = _state.value.latestGlyph)
    }

    /**
     * Quick Pass ends in motion: if the writer app-switches away after the
     * passive unlock, seal immediately so nothing is lost. Daily sessions are
     * left untouched — the practice ends in stillness (iOS `sealIfLeftInMotion`).
     */
    fun sealIfLeftInMotion() {
        if (!hasAppliedPassiveQuickUnlock) return
        if (!writer.isStarted || writer.isClosed) return
        if (sealedSession != null) return
        sealSession()
    }

    /** iOS `consumeWriteBeforeScrollAvailableUnlockGrant` (logs `unlock_tapped`). */
    fun consumeAvailableUnlockGrant(): UnlockGrant? {
        val grant = availableUnlockGrant ?: return null
        gateSession?.log(
            WriteBeforeScrollEventName.UnlockTapped,
            at = Instant.ofEpochMilli(nowMs()),
            sessionId = sessionMetrics.sessionId,
            tierRawValue = grant.tier.rawValue,
        )
        availableUnlockGrant = null
        _state.value = deriveState(latestGlyph = _state.value.latestGlyph)
        return grant
    }

    /**
     * The sealing screen's gate button when a grant is held: apply it (unless
     * a passive apply already opened the door), close the first gate for
     * gate-originated sessions, and hand the grant to the blocking runtime.
     * Mirrors iOS AppRoot `grantWriteBeforeScrollUnlock`.
     */
    fun applySealingUnlock(): UnlockGrant? {
        val sealed = sealedSession
        val grant = consumeAvailableUnlockGrant() ?: sealed?.unlockGrant ?: return null
        if (isGateOriginatedSession) {
            gateSession?.markFirstGateCompleted()
        }
        val alreadyApplied =
            (grant.tier == UnlockTier.Quick && hasAppliedPassiveQuickUnlock) ||
                (grant.tier == UnlockTier.Daily && hasAppliedPassiveDailyUnlockUpgrade)
        if (!alreadyApplied) {
            gateSession?.applyGrant(grant)
            onApplyUnlock(grant)
        }
        return grant
    }

    /**
     * Called by the sealing flow the moment the free-target moment actually
     * renders — this is what starts the once-per-day clock.
     */
    fun markFreeTargetMomentPresented() {
        gateSession?.markFreeTargetMomentShown(Instant.ofEpochMilli(nowMs()))
    }

    /**
     * Starts the mirror beat for the sealed session. Entitled writers stream a
     * reflection; free sessions make zero LLM calls — the veil stands where
     * the reflection would (iOS PostSessionSealingView.startIfNeeded).
     */
    fun beginSealedSessionReflection() {
        val sealed = sealedSession ?: return
        if (sealedReflectionStartedForHash == sealed.artifact.hash) return
        sealedReflectionStartedForHash = sealed.artifact.hash

        val existing = reflectionStore.load(sealed.artifact.hash)
        if (existing != null) {
            sealedReflectionMarkdown = removingRepeatedOpening(existing.reflection)
            sealedReflectionResolved = true
            _state.value = deriveState(latestGlyph = _state.value.latestGlyph)
            return
        }
        if (!entitledForGating()) {
            sealedReflectionVeiled = true
            sealedReflectionResolved = true
            _state.value = deriveState(latestGlyph = _state.value.latestGlyph)
            return
        }

        sealedReflectionStreamRaw = ""
        sealedReflectionJob?.cancel()
        sealedReflectionJob = viewModelScope.launch(nudgeDispatcher) {
            runCatching {
                val bytes = sealed.artifact.text.toByteArray(Charsets.UTF_8)
                val payload = reflectionRequester(
                    bytes,
                    identityProvider(),
                    "${BuildConfig.VERSION_NAME}(${BuildConfig.VERSION_CODE})",
                ) { chunk ->
                    sealedReflectionStreamRaw += chunk
                    sealedReflectionMarkdown = removingRepeatedOpening(sealedReflectionStreamRaw)
                    _state.value = deriveState(latestGlyph = _state.value.latestGlyph)
                }
                if (payload.hash != sealed.artifact.hash) throw MirrorClientError.HashMismatch
                val reflection = LocalReflection(
                    hash = payload.hash,
                    title = payload.title,
                    reflection = payload.reflection,
                    createdAt = Instant.ofEpochMilli(nowMs()),
                    creditsRemaining = payload.creditsRemaining,
                    tags = payload.tags,
                )
                reflectionStore.save(reflection)
                indexStore.updateReflection(payload.hash, payload.title, payload.tags)
                payload.reflection
            }.onSuccess { reflection ->
                sealedReflectionMarkdown = removingRepeatedOpening(reflection)
                sealedReflectionResolved = true
                sealedReflectionFailed = false
                _state.value = deriveState(latestGlyph = _state.value.latestGlyph)
            }.onFailure {
                sealedReflectionResolved = true
                sealedReflectionFailed = sealedReflectionMarkdown.isBlank()
                _state.value = deriveState(latestGlyph = _state.value.latestGlyph)
            }
        }
    }

    /** The sealing screen's Done: back to the main surface (iOS `finishSealingToMainScreen`). */
    fun finishSealing() {
        clearSealingState()
        keyboardFocusRequestId += 1
        _state.value = deriveState()
    }

    /** The sealing screen's "or stay": continue the sealed page in place. */
    fun stayAfterSealing(): Boolean {
        val sealed = sealedSession ?: return false
        clearSealingState()
        val continued = continueSession(sealed.artifact)
        if (!continued) {
            keyboardFocusRequestId += 1
            _state.value = deriveState()
        }
        return continued
    }

    fun dismissCurrentPrompt() {
        nudgeJob?.cancel()
        nudgeClearJob?.cancel()
        errorClearJob?.cancel()
        rejectedInputClearJob?.cancel()
        nudgeMessage = null
        isRequestingNudge = false
        visibleErrorMessage = null
        recentErrorMessage = null
        rejectedInputMessage = null
        _state.update {
            it.copy(
                nudgeMessage = null,
                isRequestingNudge = false,
                errorMessage = null,
                rejectedInputMessage = null,
            )
        }
    }

    fun abandonIfEmpty() {
        if (writer.isStarted) {
            activeDraftStore.save(writer.text)
        } else {
            activeDraftStore.clear()
        }
    }

    fun consumeCompletedHash() {
        _state.update { it.copy(completedHash = null) }
    }

    fun clearCompletedSession() {
        closeJob?.cancel()
        nudgeJob?.cancel()
        nudgeClearJob?.cancel()
        errorClearJob?.cancel()
        rejectedInputClearJob?.cancel()
        writer = AnkyWriter()
        sessionStartMs = null
        displayedText = ""
        displayedGlyphs = emptyList()
        acceptedGlyphCount = 0
        isFrozenForContinuation = false
        continuedArtifactToReplace = null
        nudgeMessage = null
        isRequestingNudge = false
        visibleErrorMessage = null
        recentErrorMessage = null
        rejectedInputMessage = null
        rejectedBackspaceCount = 0
        rejectedEnterCount = 0
        lastLocalNudgeAtMs = null
        localNudgeOffset = 0
        clearSealingState()
        resetWriteBeforeScrollSessionState()
        activeDraftStore.clear()
        keyboardFocusRequestId += 1
        _state.value = deriveState()
    }

    fun continueSession(artifact: SavedAnky): Boolean {
        if (artifact.isComplete) {
            clearCompletedSession()
            return false
        }
        return runCatching {
            val restored = AnkyWriter.fromDraft(artifact.text)
            if (restored.isClosed) error("Closed .anky artifacts cannot be continued.")
            val parsed = AnkyParser.parse(artifact.text)
            closeJob?.cancel()
            nudgeJob?.cancel()
            nudgeClearJob?.cancel()
            errorClearJob?.cancel()
            writer = restored
            sessionStartMs = parsed.startEpochMs
            displayedText = AnkyReconstructor.reconstructText(parsed)
            displayedGlyphs = displayedText.map { WritingGlyph(it.toString(), 1f) }
            acceptedGlyphCount = parsed.events.size
            nudgeMessage = null
            isRequestingNudge = false
            visibleErrorMessage = null
            recentErrorMessage = null
            rejectedInputMessage = null
            isFrozenForContinuation = true
            continuedArtifactToReplace = artifact
            activeDraftStore.save(writer.text)
            keyboardFocusRequestId += 1
            continuationScrollRequestId += 1
            _state.value = deriveState()
        }.isSuccess
    }

    fun refreshLiveState() {
        if (writer.isStarted) _state.value = deriveState(latestGlyph = _state.value.latestGlyph)
    }

    fun resetAfterAccountDeletion() {
        closeJob?.cancel()
        nudgeJob?.cancel()
        nudgeClearJob?.cancel()
        errorClearJob?.cancel()
        rejectedInputClearJob?.cancel()
        writer = AnkyWriter()
        sessionStartMs = null
        displayedText = ""
        displayedGlyphs = emptyList()
        acceptedGlyphCount = 0
        isFrozenForContinuation = false
        continuedArtifactToReplace = null
        nudgeMessage = null
        isRequestingNudge = false
        visibleErrorMessage = null
        recentErrorMessage = null
        rejectedInputMessage = null
        rejectedBackspaceCount = 0
        rejectedEnterCount = 0
        lastLocalNudgeAtMs = null
        localNudgeOffset = 0
        clearSealingState()
        resetWriteBeforeScrollSessionState()
        activeDraftStore.clear()
        _state.value = deriveState()
    }

    private fun scheduleClose(afterMs: Long) {
        closeJob?.cancel()
        closeJob = viewModelScope.launch(dispatcher) {
            delay(maxOf(0, afterMs))
            closeAfterTerminalSilence()
        }
    }

    private fun closeAfterTerminalSilence() {
        if (!writer.isStarted) return
        sealSession()
    }

    private fun sealSession() {
        if (!writer.isStarted) return
        if (sealedSession != null) return
        val text = writer.text
        val sealedAtMs = nowMs()
        val sealedAt = Instant.ofEpochMilli(sealedAtMs)
        val replacedDurationMs = continuedArtifactToReplace?.durationMs
        activeDraftStore.save(text)
        runCatching {
            val inputStats = WritingInputStats(
                backspaceCount = rejectedBackspaceCount,
                enterCount = rejectedEnterCount,
            )
            val artifact = archive.save(text, inputStats)
            val summary = SessionSummary.make(artifact, reflectionStore.load(artifact.hash))
            indexStore.upsert(summary)
            artifact
        }.onSuccess { artifact ->
            val replacedArtifact = continuedArtifactToReplace
            if (replacedArtifact != null && replacedArtifact.hash != artifact.hash) {
                runCatching { archive.delete(replacedArtifact.hash) }
                runCatching { indexStore.delete(replacedArtifact.hash) }
            }
            continuedArtifactToReplace = null
            if (artifact.isComplete) {
                activeDraftStore.clear()
            } else {
                activeDraftStore.save(text)
            }
            // Level credit, synchronously before any UI transition
            // (iOS: levelProgressStore.creditSealedSession + flushUnreported).
            onSealedComplete(artifact.hash, artifact.durationMs, replacedDurationMs, sealedAtMs)
            recordSealForGate(artifact, sealedAt)
            sealedSession = makeSealedSession(artifact, sealedAt)
            sealedReflectionMarkdown = ""
            sealedReflectionResolved = false
            sealedReflectionFailed = false
            sealedReflectionVeiled = false
            sealedReflectionStartedForHash = null
            visibleErrorMessage = null
            recentErrorMessage = null
            rejectedInputMessage = null
            resetInMemoryWriterAfterSeal()
            _state.value = deriveState().copy(
                elapsedMs = artifact.durationMs,
                silenceElapsedMs = AnkyDuration.TerminalSilenceMs,
                silenceRemainingMs = 0,
                progress = (artifact.durationMs.toFloat() / AnkyDuration.CompleteRitualMs).coerceIn(0f, 1f),
                isClosing = false,
            )
        }.onFailure {
            activeDraftStore.save(text)
            showPersistentError("Could not save this .anky.", isClosing = false)
        }
    }

    private fun recordSealForGate(artifact: SavedAnky, sealedAt: Instant) {
        val gate = gateSession ?: return
        gate.markWrote(sealedAt)
        gate.log(
            WriteBeforeScrollEventName.WbsSessionSealed,
            at = sealedAt,
            sessionId = sessionMetrics.sessionId,
            tierRawValue = sessionMetrics.finalTierRawValue,
            metadata = mapOf("durationMs" to "${artifact.durationMs}"),
        )
        val targetMs = gate.dailyTargetMs(sealedAt)
        if (artifact.durationMs > targetMs) {
            gate.log(
                WriteBeforeScrollEventName.SessionOvershoot,
                at = sealedAt,
                sessionId = sessionMetrics.sessionId,
                metadata = mapOf(
                    "targetMs" to "$targetMs",
                    "durationMs" to "${artifact.durationMs}",
                ),
            )
        }
    }

    private fun makeSealedSession(artifact: SavedAnky, sealedAt: Instant): SealedWritingSession {
        val grant = availableUnlockGrant
        val targetMs = gateSession?.dailyTargetMs(sealedAt) ?: dailyTargetMs
        // Decision 2026-07-06 (option C): a free writer's target crossing is
        // acknowledged where a subscriber's day would open. Entitlement is
        // re-checked at seal so a mid-session purchase wins, and an earned
        // unlock CTA always keeps its button (iOS AppRoot.revealOnMap).
        val showsFreeTargetMoment = freeTargetMomentPending &&
            !entitledForGating() &&
            grant == null
        return SealedWritingSession(
            artifact = artifact,
            unlockGrant = grant,
            isGateOriginated = isGateOriginatedSession,
            gateOriginAppDisplayName = gateOriginAppDisplayName,
            showsFreeTargetMoment = showsFreeTargetMoment,
            quickPassesRemaining = quickPassesRemaining,
            remainingToTargetMs = maxOf(0, targetMs - artifact.durationMs),
            isFirstGate = grant != null && gateSession?.hasCompletedFirstGate == false,
        )
    }

    private fun resetInMemoryWriterAfterSeal() {
        closeJob?.cancel()
        nudgeJob?.cancel()
        nudgeClearJob?.cancel()
        writer = AnkyWriter()
        sessionStartMs = null
        displayedText = ""
        displayedGlyphs = emptyList()
        acceptedGlyphCount = 0
        isFrozenForContinuation = false
        continuedArtifactToReplace = null
        nudgeMessage = null
        isRequestingNudge = false
        rejectedBackspaceCount = 0
        rejectedEnterCount = 0
        lastLocalNudgeAtMs = null
        localNudgeOffset = 0
    }

    private fun clearSealingState() {
        sealedReflectionJob?.cancel()
        sealedSession = null
        sealedReflectionMarkdown = ""
        sealedReflectionResolved = false
        sealedReflectionFailed = false
        sealedReflectionVeiled = false
        sealedReflectionStartedForHash = null
        sealedReflectionStreamRaw = ""
        resetWriteBeforeScrollSessionState()
    }

    private fun resetWriteBeforeScrollSessionState() {
        sessionTracker.reset()
        sessionMetrics = sessionTracker.metrics
        availableUnlockGrant = null
        quickPassUnlockLine = null
        hasAppliedPassiveQuickUnlock = false
        hasAppliedPassiveDailyUnlockUpgrade = false
        freeTargetMomentPending = false
        isGateOriginatedSession = false
        gateOriginAppDisplayName = null
    }

    private fun refreshGateBaselines(at: Instant) {
        val gate = gateSession ?: return
        dailyTargetMs = gate.dailyTargetMs(at)
        quickPassesRemaining = gate.quickPassesRemaining(at)
    }

    /**
     * A held daily grant stays valid while the shield is already open (the
     * upgrade path); a quick offer is withdrawn once unlocked
     * (iOS `refreshWriteBeforeScrollUnlockOffer`).
     */
    private fun refreshUnlockOffer(at: Instant) {
        val gate = gateSession ?: return
        val grant = availableUnlockGrant ?: return
        if (grant.tier == UnlockTier.Quick && !gate.shouldOfferUnlock(at)) {
            availableUnlockGrant = null
        }
    }

    private fun recordWriteBeforeScrollProgress(acceptedCharacterCount: Int, epochMs: Long) {
        val gate = gateSession ?: return
        val at = Instant.ofEpochMilli(epochMs)
        val targetMs = gate.dailyTargetMs(at)
        val passesRemaining = gate.quickPassesRemaining(at)
        val entitled = entitledForGating()
        dailyTargetMs = targetMs
        quickPassesRemaining = passesRemaining
        val snapshot = GateWritingSnapshot(
            reconstructedText = displayedText,
            elapsedMs = writer.writingElapsedMs,
        )

        val update = sessionTracker.recordAcceptedCharacters(
            count = acceptedCharacterCount,
            snapshot = snapshot,
            at = at,
            dailyTargetMs = targetMs,
            quickPassesRemaining = passesRemaining,
            dailyUnlockEntitled = entitled,
        )
        sessionMetrics = update.metrics

        for (event in update.events) {
            val metadata = if (event == WriteBeforeScrollEventName.DailyTargetReached) {
                mapOf(
                    "targetMs" to "$targetMs",
                    "elapsedMs" to "${update.metrics.elapsedMs}",
                )
            } else {
                emptyMap()
            }
            gate.log(
                event,
                at = at,
                sessionId = update.metrics.sessionId,
                tierRawValue = tierFor(event)?.rawValue,
                metadata = metadata,
            )
        }

        val currentGrant = update.availableGrant ?: gate.grant(
            snapshot = snapshot,
            at = at,
            dailyTargetMs = targetMs,
            quickPassesRemaining = passesRemaining,
            dailyUnlockEntitled = entitled,
        )
        val action = gate.ladderAction(
            grant = currentGrant,
            isGateOriginatedSession = isGateOriginatedSession,
            hasAppliedPassiveQuickUnlock = hasAppliedPassiveQuickUnlock,
            hasAppliedDailyUnlockUpgrade = hasAppliedPassiveDailyUnlockUpgrade,
            dailyUnlockEntitled = entitled,
            hasReachedDailyTarget = snapshot.elapsedMs >= targetMs,
            hasOfferedFreeTargetMoment = freeTargetMomentPending || gate.wasFreeTargetMomentShown(at),
            at = at,
        )
        when (action) {
            is WriteBeforeScrollUnlockLadderAction.Offer -> offerUnlock(action.grant)
            is WriteBeforeScrollUnlockLadderAction.ApplyQuickPassively -> {
                offerUnlock(action.grant)
                applyPassiveQuickUnlock(action.grant, at)
            }
            is WriteBeforeScrollUnlockLadderAction.UpgradeToDaily -> {
                offerUnlock(action.grant)
                applyPassiveDailyUnlockUpgrade(action.grant)
            }
            WriteBeforeScrollUnlockLadderAction.OfferFreeTargetMoment -> {
                // Held for the sealing flow; any pending grant is untouched —
                // the next keystroke resolves it normally.
                freeTargetMomentPending = true
            }
            WriteBeforeScrollUnlockLadderAction.Withdraw -> {
                availableUnlockGrant = null
            }
        }
    }

    private fun offerUnlock(grant: UnlockGrant) {
        val previousTier = availableUnlockGrant?.tier
        availableUnlockGrant = grant
        if (previousTier != grant.tier) {
            onUnlockAvailable(grant)
        }
    }

    /**
     * §5.4: the moment the sentence completes, the Quick Pass unlock applies
     * by itself — no button, no stillness. The ladder only routes here for
     * gate-originated sessions; organic sessions never surface or spend a pass.
     */
    private fun applyPassiveQuickUnlock(grant: UnlockGrant, at: Instant) {
        if (hasAppliedPassiveQuickUnlock) return
        hasAppliedPassiveQuickUnlock = true
        gateSession?.applyQuickPassUnlock(grant, at, sessionMetrics.sessionId)
        quickPassesRemaining = gateSession?.quickPassesRemaining(at) ?: quickPassesRemaining
        onApplyUnlock(grant)
        if (isGateOriginatedSession) {
            quickPassUnlockLine = AnkyCopyRegistry.quickPassUnlockLine(gateOriginAppDisplayName)
        }
    }

    /**
     * Crossing the daily target while a Quick Pass window is open upgrades
     * the writer to the full-day unlock on the spot.
     */
    private fun applyPassiveDailyUnlockUpgrade(grant: UnlockGrant) {
        if (hasAppliedPassiveDailyUnlockUpgrade) return
        hasAppliedPassiveDailyUnlockUpgrade = true
        gateSession?.applyGrant(grant)
        onApplyUnlock(grant)
    }

    private fun tierFor(event: WriteBeforeScrollEventName): UnlockTier? =
        when (event) {
            WriteBeforeScrollEventName.SentenceUnlockAvailable -> UnlockTier.Quick
            WriteBeforeScrollEventName.DailyTargetReached -> UnlockTier.Daily
            else -> null
        }

    private fun scheduleCloseForRestoredDraft() {
        if (!writer.isStarted) return
        if (writer.isClosed) return
        val lastAcceptedMs = writer.lastAcceptedMs ?: return
        val silenceElapsedMs = nowMs() - lastAcceptedMs
        scheduleClose(afterMs = AnkyDuration.TerminalSilenceMs - silenceElapsedMs)
    }

    private fun deriveState(latestGlyph: String = ""): WriteState {
        val validation = AnkyValidator.validate(writer.text)
        val now = nowMs()
        val elapsed = if (writer.isClosed) {
            (validation as? AnkyValidation.Valid)?.durationMs ?: 0
        } else if (isFrozenForContinuation) {
            writer.writingElapsedMs
        } else {
            writer.writingElapsedMs
        }
        val silenceElapsed = if (writer.isClosed) {
            AnkyDuration.TerminalSilenceMs
        } else if (isFrozenForContinuation) {
            0
        } else {
            writer.lastAcceptedMs?.let { maxOf(0, now - it) } ?: 0
        }
        updateLatestGlyphColorProgress(silenceElapsed)
        return WriteState(
            latestGlyph = latestGlyph,
            displayedText = displayedText,
            displayedGlyphs = displayedGlyphs,
            elapsedMs = elapsed,
            silenceElapsedMs = silenceElapsed,
            silenceRemainingMs = maxOf(0, AnkyDuration.TerminalSilenceMs - silenceElapsed),
            progress = (elapsed.toFloat() / AnkyDuration.CompleteRitualMs).coerceIn(0f, 1f),
            isClosing = writer.isStarted && !writer.isClosed && !isFrozenForContinuation,
            acceptedGlyphCount = acceptedGlyphCount,
            todayAnkyCount = todayAnkyCount(now),
            keyboardFocusRequestId = keyboardFocusRequestId,
            continuationScrollRequestId = continuationScrollRequestId,
            errorMessage = visibleErrorMessage,
            nudgeMessage = nudgeMessage,
            isRequestingNudge = isRequestingNudge,
            isFrozenForContinuation = isFrozenForContinuation,
            rejectedInputPulseId = rejectedInputPulseId,
            rejectedInputMessage = rejectedInputMessage,
            rejectedBackspaceCount = rejectedBackspaceCount,
            rejectedEnterCount = rejectedEnterCount,
            writingPreferences = writingPreferences,
            sessionMetrics = sessionMetrics,
            availableUnlockGrant = availableUnlockGrant,
            quickPassesRemaining = quickPassesRemaining,
            quickPassUnlockLine = quickPassUnlockLine,
            hasAppliedPassiveQuickUnlock = hasAppliedPassiveQuickUnlock,
            dailyTargetMs = dailyTargetMs,
            sealedSession = sealedSession,
            sealedReflectionMarkdown = sealedReflectionMarkdown,
            sealedReflectionResolved = sealedReflectionResolved,
            sealedReflectionFailed = sealedReflectionFailed,
            sealedReflectionVeiled = sealedReflectionVeiled,
        )
    }

    private fun resumeIfFrozen(now: Long) {
        if (!isFrozenForContinuation) return
        writer.prepareToResume(now)
        isFrozenForContinuation = false
        scheduleClose(afterMs = AnkyDuration.TerminalSilenceMs)
    }

    private fun todayAnkyCount(now: Long): Int {
        val today = Instant.ofEpochMilli(now).atZone(ZoneOffset.UTC).toLocalDate()
        return indexStore.load().count { summary ->
            summary.isComplete && summary.createdAt.atZone(ZoneOffset.UTC).toLocalDate() == today
        }
    }

    private fun requestAnkyNudge(text: String) {
        runCatching {
            val bytes = text.toByteArray(Charsets.UTF_8)
            val payload = nudgeRequester(
                bytes,
                identityProvider(),
                "${BuildConfig.VERSION_NAME}(${BuildConfig.VERSION_CODE})",
                MirrorIntent.Nudge,
            )
            if (payload.hash != AnkyHasher.sha256Hex(bytes)) throw MirrorClientError.HashMismatch
            oneLineNudge(payload.reflection)
        }.onSuccess { message ->
            isRequestingNudge = false
            showTransientNudge(message)
        }.onFailure { error ->
            isRequestingNudge = false
            showTransientNudge(nudgeErrorMessage(error.message.orEmpty()))
        }
    }

    /** The free writer's local themed nudge (iOS `showContextualNudge`). */
    private fun showContextualNudge() {
        val now = nowMs()
        val lastAt = lastLocalNudgeAtMs
        if (lastAt != null && now - lastAt < 3_000) {
            if (nudgeMessage != null) {
                _state.value = deriveState(latestGlyph = _state.value.latestGlyph)
            }
            return
        }
        val writing = displayedText.ifEmpty { writer.text }
        val message = AnkyNudgeGenerator.generateNudge(
            writing = writing,
            timeWrittenSeconds = writer.writingElapsedMs / 1000.0,
            wordCount = writing.split(Regex("\\s+")).count { it.isNotBlank() },
            offset = localNudgeOffset,
        )
        localNudgeOffset += 1
        lastLocalNudgeAtMs = now
        showTransientNudge(message)
    }

    private fun showTransientNudge(message: String) {
        nudgeClearJob?.cancel()
        nudgeMessage = message
        _state.value = deriveState(latestGlyph = _state.value.latestGlyph)
        nudgeClearJob = viewModelScope.launch(dispatcher) {
            delay(6_000)
            if (nudgeMessage == message) {
                nudgeMessage = null
                _state.value = deriveState(latestGlyph = _state.value.latestGlyph)
            }
        }
    }

    private fun showRejectedInputLine(message: String) {
        rejectedInputClearJob?.cancel()
        rejectedInputMessage = message
        recentErrorMessage = message
        _state.value = deriveState(latestGlyph = _state.value.latestGlyph)
        rejectedInputClearJob = viewModelScope.launch(dispatcher) {
            delay(2_000)
            if (rejectedInputMessage == message) {
                rejectedInputMessage = null
                _state.value = deriveState(latestGlyph = _state.value.latestGlyph)
            }
            delay(5_000)
            if (recentErrorMessage == message) {
                recentErrorMessage = null
            }
        }
    }

    private fun showTransientError(message: String) {
        visibleErrorMessage = message
        recentErrorMessage = message
        _state.value = deriveState(latestGlyph = _state.value.latestGlyph)
        scheduleErrorFade(message, keepRecall = false)
    }

    private fun showPersistentError(message: String, isClosing: Boolean? = null) {
        errorClearJob?.cancel()
        visibleErrorMessage = message
        recentErrorMessage = null
        val nextState = deriveState(latestGlyph = _state.value.latestGlyph)
        _state.value = if (isClosing == null) nextState else nextState.copy(isClosing = isClosing)
    }

    private fun scheduleErrorFade(message: String, keepRecall: Boolean) {
        errorClearJob?.cancel()
        errorClearJob = viewModelScope.launch(dispatcher) {
            delay(2_000)
            if (visibleErrorMessage == message) {
                visibleErrorMessage = null
                _state.value = deriveState(latestGlyph = _state.value.latestGlyph)
            }
            if (!keepRecall) {
                delay(5_000)
                if (recentErrorMessage == message) {
                    recentErrorMessage = null
                }
            }
        }
    }

    private fun freezeLatestGlyph(now: Long) {
        val lastAcceptedMs = writer.lastAcceptedMs ?: return
        updateLatestGlyphColorProgress(maxOf(0, now - lastAcceptedMs))
    }

    private fun updateLatestGlyphColorProgress(silenceElapsedMs: Long) {
        if (displayedGlyphs.isEmpty()) return
        val progress = (silenceElapsedMs.toFloat() / AnkyDuration.TerminalSilenceMs).coerceIn(0f, 1f)
        displayedGlyphs = displayedGlyphs.dropLast(1) + displayedGlyphs.last().copy(silenceProgress = progress)
    }

    private fun activeDraftForToday(): String? {
        val text = activeDraftStore.load()?.takeIf { it.isNotBlank() } ?: return null
        val parsed = runCatching { AnkyParser.parse(text) }.getOrNull() ?: return text
        val startDay = Instant.ofEpochMilli(parsed.startEpochMs).atZone(ZoneOffset.UTC).toLocalDate()
        val today = Instant.ofEpochMilli(nowMs()).atZone(ZoneOffset.UTC).toLocalDate()
        if (startDay != today) {
            activeDraftStore.clear()
            return null
        }
        return text
    }

    private fun restoredStartMs(): Long? =
        runCatching { AnkyParser.parse(writer.text).startEpochMs }.getOrNull()

    private fun restoredDisplayedText(): String =
        runCatching { AnkyReconstructor.reconstructText(AnkyParser.parse(writer.text)) }.getOrDefault("")

    private fun restoredGlyphCount(): Int =
        runCatching { AnkyParser.parse(writer.text).events.size }.getOrDefault(0)

    companion object {
        /**
         * Streamed reflections sometimes repeat their opening; show it once
         * (port of iOS PostSessionSealingView.removingRepeatedOpening).
         */
        fun removingRepeatedOpening(text: String): String {
            val trimmed = text.trim()
            if (trimmed.length < 40) return trimmed

            val maxPrefixLength = minOf(trimmed.length / 2, 140)
            if (maxPrefixLength < 20) return trimmed

            for (length in maxPrefixLength downTo 20) {
                val prefix = trimmed.substring(0, length)
                val rest = trimmed.substring(length)
                if (rest.startsWith(prefix)) {
                    return rest.trim()
                }
            }

            return trimmed
        }
    }
}

private fun oneLineNudge(text: String): String {
    val cleaned = text
        .replace("\r\n", "\n")
        .lineSequence()
        .map { it.trim() }
        .firstOrNull { it.isNotEmpty() }
        ?: text.trim()
    val withoutHeading = cleaned.replace(Regex("^#+\\s*"), "")
    return withoutHeading.ifBlank { "stay with the next true sentence." }
}

private fun nudgeErrorMessage(message: String): String =
    when {
        message.contains("credit", ignoreCase = true) || message.contains("entitle", ignoreCase = true) ->
            "nudges open with anky's subscription. the writing is still yours."
        message.contains("incomplete", ignoreCase = true) -> "the mirror is not ready to nudge unfinished ankys yet."
        else -> "anky could not return a nudge right now."
    }
