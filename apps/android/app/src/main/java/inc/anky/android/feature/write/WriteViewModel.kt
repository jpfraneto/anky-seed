package inc.anky.android.feature.write

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import inc.anky.android.core.protocol.AnkyDuration
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
    val elapsedMs: Long = 0,
    val silenceElapsedMs: Long = 0,
    val silenceRemainingMs: Long = AnkyDuration.TerminalSilenceMs,
    val progress: Float = 0f,
    val isClosing: Boolean = false,
    val completedHash: String? = null,
    val acceptedGlyphCount: Int = 0,
    val errorMessage: String? = null,
) {
    val hasReachedRitualMark: Boolean
        get() = elapsedMs >= AnkyDuration.CompleteRitualMs
}

class WriteViewModel(
    private val activeDraftStore: ActiveDraftStore,
    private val archive: LocalAnkyArchive,
    private val reflectionStore: ReflectionStore,
    private val indexStore: SessionIndexStore,
    private val nowMs: () -> Long = { System.currentTimeMillis() },
    private val dispatcher: CoroutineDispatcher = Dispatchers.Main,
) : ViewModel() {
    private val restoredDraftText = activeDraftForToday()
    private val restoredWriterResult = restoredDraftText?.let { runCatching { AnkyWriter.fromDraft(it) } }
    private val restoreErrorMessage =
        if (restoredWriterResult?.isFailure == true) "Could not restore the active draft." else null
    private var writer: AnkyWriter = restoredWriterResult?.getOrNull() ?: AnkyWriter()
    private var closeJob: Job? = null
    private var sessionStartMs: Long? = restoredStartMs()
    private var displayedText: String = restoredDisplayedText()
    private var acceptedGlyphCount = restoredGlyphCount()
    private var frozenAtMs: Long? = null

    private val _state = MutableStateFlow(deriveState().copy(errorMessage = restoreErrorMessage))
    val state: StateFlow<WriteState> = _state

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
        if (frozenAtMs != null) {
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
        if (!writer.isStarted) sessionStartMs = now
        resumeIfFrozen(now)
        if (!writer.accept(glyph, now)) return
        displayedText += glyph
        acceptedGlyphCount += 1
        activeDraftStore.save(writer.text)
        scheduleClose(afterMs = AnkyDuration.TerminalSilenceMs)
        _state.value = deriveState(latestGlyph = glyph)
    }

    fun ignoreBackspaceOrReplacement() {
        _state.update { it.copy(isClosing = writer.isStarted) }
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

    private fun scheduleClose(afterMs: Long) {
        closeJob?.cancel()
        closeJob = viewModelScope.launch(dispatcher) {
            delay(maxOf(0, afterMs))
            freezeOrSealSession()
        }
    }

    private fun freezeOrSealSession() {
        if (!writer.isStarted) return
        if (wouldBeCompleteWithTerminalSilence()) {
            sealSession()
        } else {
            freezeSession()
        }
    }

    private fun freezeSession() {
        if (!writer.isStarted) return
        val text = writer.text
        runCatching {
            activeDraftStore.save(text)
            val artifact = archive.save(text)
            val summary = SessionSummary.make(artifact, reflectionStore.load(artifact.hash))
            indexStore.upsert(summary)
        }.onSuccess {
            frozenAtMs = writer.lastAcceptedMs?.plus(AnkyDuration.TerminalSilenceMs) ?: nowMs()
            _state.value = deriveState().copy(isClosing = false, errorMessage = null)
        }.onFailure {
            _state.value = deriveState().copy(
                isClosing = false,
                errorMessage = "Could not save this .anky.",
            )
        }
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
            writer = AnkyWriter()
            displayedText = ""
            sessionStartMs = null
            acceptedGlyphCount = 0
            frozenAtMs = null
            _state.value = deriveState().copy(completedHash = artifact.hash, isClosing = false, errorMessage = null)
        }.onFailure {
            activeDraftStore.save(text)
            _state.value = deriveState().copy(
                isClosing = false,
                errorMessage = "Could not save this .anky.",
            )
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
        val now = frozenAtMs ?: nowMs()
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
        return WriteState(
            latestGlyph = latestGlyph,
            displayedText = displayedText,
            elapsedMs = elapsed,
            silenceElapsedMs = silenceElapsed,
            silenceRemainingMs = maxOf(0, AnkyDuration.TerminalSilenceMs - silenceElapsed),
            progress = (elapsed.toFloat() / AnkyDuration.CompleteRitualMs).coerceIn(0f, 1f),
            isClosing = writer.isStarted && frozenAtMs == null && !writer.isClosed,
            acceptedGlyphCount = acceptedGlyphCount,
        )
    }

    private fun resumeIfFrozen(now: Long) {
        val frozenAt = frozenAtMs ?: return
        val sessionStart = sessionStartMs
        if (sessionStart != null) {
            sessionStartMs = sessionStart + maxOf(0, now - frozenAt)
        }
        writer.prepareToResume(now)
        frozenAtMs = null
    }

    private fun wouldBeCompleteWithTerminalSilence(): Boolean =
        runCatching {
            val parsed = AnkyParser.parse(writer.text)
            AnkyDuration.durationMs(parsed) + AnkyDuration.TerminalSilenceMs >= AnkyDuration.CompleteRitualMs
        }.getOrDefault(false)

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
