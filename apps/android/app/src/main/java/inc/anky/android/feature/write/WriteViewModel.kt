package inc.anky.android.feature.write

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import inc.anky.android.BuildConfig
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
import inc.anky.android.core.storage.ReflectionStore
import inc.anky.android.core.storage.SessionIndexStore
import inc.anky.android.core.storage.SessionSummary
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
    val errorMessage: String? = null,
    val nudgeMessage: String? = null,
    val isRequestingNudge: Boolean = false,
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
    private var nudgeMessage: String? = null
    private var isRequestingNudge = false
    private var visibleErrorMessage: String? = restoreErrorMessage
    private var recentErrorMessage: String? = null
    private var keyboardFocusRequestId = 0

    private val _state = MutableStateFlow(deriveState())
    val state: StateFlow<WriteState> = _state
    val devSampleAnkyArtifact: String
        get() = DevAnkyFixture.validArtifact

    init {
        scheduleCloseForRestoredDraft()
    }

    fun acceptGlyph(glyph: String) {
        val now = nowMs()
        acceptGlyphAt(glyph, now)
    }

    fun acceptGlyphs(glyphs: List<String>) {
        if (glyphs.isEmpty()) return
        val now = nowMs()
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
        freezeLatestGlyph(now)
        if (!writer.isStarted) sessionStartMs = now
        if (!writer.accept(glyph, now)) return
        displayedText += glyph
        displayedGlyphs = displayedGlyphs + WritingGlyph(glyph, 0f)
        acceptedGlyphCount += 1
        activeDraftStore.save(writer.text)
        scheduleClose(afterMs = AnkyDuration.TerminalSilenceMs)
        _state.value = deriveState(latestGlyph = glyph)
    }

    fun ignoreBackspaceOrReplacement() {
        showTransientError("that doesn't work here. just keep writing without agenda.")
    }

    fun startAnkyNudgeIfPossible(): Boolean {
        if (!writer.isStarted || writer.text.isBlank()) return false
        if (_state.value.shouldShowNudgeDialogue) return true

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
        keyboardFocusRequestId += 1
        _state.value = deriveState(latestGlyph = _state.value.latestGlyph)
    }

    fun dismissCurrentPrompt() {
        nudgeJob?.cancel()
        nudgeClearJob?.cancel()
        errorClearJob?.cancel()
        nudgeMessage = null
        isRequestingNudge = false
        visibleErrorMessage = null
        recentErrorMessage = null
        _state.update { it.copy(nudgeMessage = null, isRequestingNudge = false, errorMessage = null) }
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

    fun refreshLiveState() {
        if (writer.isStarted) _state.value = deriveState(latestGlyph = _state.value.latestGlyph)
    }

    fun resetAfterAccountDeletion() {
        closeJob?.cancel()
        nudgeJob?.cancel()
        nudgeClearJob?.cancel()
        errorClearJob?.cancel()
        writer = AnkyWriter()
        sessionStartMs = null
        displayedText = ""
        displayedGlyphs = emptyList()
        acceptedGlyphCount = 0
        nudgeMessage = null
        isRequestingNudge = false
        visibleErrorMessage = null
        recentErrorMessage = null
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
        if (!writer.isClosed) writer.closeWithTerminalSilence()
        val text = writer.text
        activeDraftStore.save(text)
        runCatching {
            val artifact = archive.save(text)
            val summary = SessionSummary.make(artifact, reflectionStore.load(artifact.hash))
            indexStore.upsert(summary)
            artifact
        }.onSuccess { artifact ->
            activeDraftStore.clear()
            visibleErrorMessage = null
            recentErrorMessage = null
            _state.value = deriveState().copy(
                completedHash = artifact.hash,
                elapsedMs = maxOf(artifact.durationMs, AnkyDuration.CompleteRitualMs),
                silenceElapsedMs = AnkyDuration.TerminalSilenceMs,
                silenceRemainingMs = 0,
                progress = 1f,
                isClosing = false,
            )
        }.onFailure {
            activeDraftStore.save(text)
            showPersistentError("Could not save this .anky.", isClosing = false)
        }
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
        } else {
            sessionStartMs?.let { maxOf(0, now - it) }
                ?: (validation as? AnkyValidation.Valid)?.durationMs
                ?: 0
        }
        val silenceElapsed = if (writer.isClosed) {
            AnkyDuration.TerminalSilenceMs
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
            isClosing = writer.isStarted && !writer.isClosed,
            acceptedGlyphCount = acceptedGlyphCount,
            todayAnkyCount = todayAnkyCount(now),
            keyboardFocusRequestId = keyboardFocusRequestId,
            errorMessage = visibleErrorMessage,
            nudgeMessage = nudgeMessage,
            isRequestingNudge = isRequestingNudge,
        )
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
        message.contains("credit", ignoreCase = true) -> "that nudge needs one credit."
        message.contains("incomplete", ignoreCase = true) -> "the mirror is not ready to nudge unfinished ankys yet."
        else -> "anky could not return a nudge right now."
    }
