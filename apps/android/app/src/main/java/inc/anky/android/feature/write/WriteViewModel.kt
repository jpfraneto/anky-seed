package inc.anky.android.feature.write

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import inc.anky.android.core.protocol.AnkyDuration
import inc.anky.android.core.protocol.AnkyValidator
import inc.anky.android.core.protocol.AnkyValidation
import inc.anky.android.core.protocol.AnkyWriter
import inc.anky.android.core.storage.ActiveDraftStore
import inc.anky.android.core.storage.LocalAnkyArchive
import inc.anky.android.core.storage.ReflectionStore
import inc.anky.android.core.storage.SessionIndexStore
import inc.anky.android.core.storage.SessionSummary
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
    val elapsedMs: Long = 0,
    val progress: Float = 0f,
    val isClosing: Boolean = false,
    val completedHash: String? = null,
)

class WriteViewModel(
    private val activeDraftStore: ActiveDraftStore,
    private val archive: LocalAnkyArchive,
    private val reflectionStore: ReflectionStore,
    private val indexStore: SessionIndexStore,
    private val nowMs: () -> Long = { System.currentTimeMillis() },
    private val dispatcher: CoroutineDispatcher = Dispatchers.Main,
) : ViewModel() {
    private var writer: AnkyWriter = activeDraftStore.load()
        ?.takeIf { it.isNotBlank() }
        ?.let { runCatching { AnkyWriter.fromDraft(it) }.getOrNull() }
        ?: AnkyWriter()
    private var closeJob: Job? = null

    private val _state = MutableStateFlow(deriveState())
    val state: StateFlow<WriteState> = _state

    init {
        scheduleCloseForRestoredDraft()
    }

    fun acceptGlyph(glyph: String) {
        if (!writer.accept(glyph, nowMs())) return
        activeDraftStore.save(writer.text)
        scheduleClose(afterMs = AnkyDuration.TerminalSilenceMs)
        _state.value = deriveState(latestGlyph = glyph)
    }

    fun ignoreBackspaceOrReplacement() {
        _state.update { it.copy(isClosing = writer.isStarted) }
    }

    private fun scheduleClose(afterMs: Long) {
        closeJob?.cancel()
        closeJob = viewModelScope.launch(dispatcher) {
            delay(maxOf(0, afterMs))
            closeSession()
        }
    }

    private fun closeSession() {
        if (!writer.isStarted) return
        if (!writer.isClosed) writer.closeWithTerminalSilence()
        val text = writer.text
        activeDraftStore.save(text)
        val artifact = archive.save(text)
        val summary = SessionSummary.make(artifact, reflectionStore.load(artifact.hash))
        indexStore.upsert(summary)
        activeDraftStore.clear()
        _state.value = deriveState().copy(completedHash = artifact.hash, isClosing = false)
        writer = AnkyWriter()
    }

    private fun scheduleCloseForRestoredDraft() {
        if (!writer.isStarted) return
        if (writer.isClosed) {
            closeJob = viewModelScope.launch(dispatcher) { closeSession() }
            return
        }
        val lastAcceptedMs = writer.lastAcceptedMs ?: return
        val silenceElapsedMs = nowMs() - lastAcceptedMs
        scheduleClose(afterMs = AnkyDuration.TerminalSilenceMs - silenceElapsedMs)
    }

    private fun deriveState(latestGlyph: String = ""): WriteState {
        val validation = AnkyValidator.validate(writer.text)
        val elapsed = (validation as? AnkyValidation.Valid)?.durationMs ?: 0
        return WriteState(
            latestGlyph = latestGlyph,
            elapsedMs = elapsed,
            progress = (elapsed.toFloat() / AnkyDuration.CompleteRitualMs).coerceIn(0f, 1f),
            isClosing = writer.isStarted,
        )
    }

}
