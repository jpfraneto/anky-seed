package inc.anky.android.feature.reveal

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import inc.anky.android.core.identity.WriterIdentityStore
import inc.anky.android.core.mirror.MirrorClient
import inc.anky.android.core.mirror.MirrorEligibility
import inc.anky.android.core.privacy.PrivacyMessages
import inc.anky.android.core.storage.LocalAnkyArchive
import inc.anky.android.core.storage.LocalReflection
import inc.anky.android.core.storage.ReflectionStore
import inc.anky.android.core.storage.SavedAnky
import inc.anky.android.core.storage.SessionIndexStore
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class RevealState(
    val artifact: SavedAnky? = null,
    val reflection: LocalReflection? = null,
    val privacyReminder: String = PrivacyMessages.RevealReminder,
    val canAskAnky: Boolean = false,
    val isAsking: Boolean = false,
    val error: String? = null,
)

class RevealViewModel(
    private val hash: String,
    private val archive: LocalAnkyArchive,
    private val reflectionStore: ReflectionStore,
    private val indexStore: SessionIndexStore,
    private val identityStore: WriterIdentityStore,
    private val mirrorClientProvider: () -> MirrorClient,
) : ViewModel() {
    private val _state = MutableStateFlow(RevealState())
    val state: StateFlow<RevealState> = _state

    init {
        load()
    }

    fun load() {
        val artifact = runCatching { archive.load(hash) }.getOrNull()
        val reflection = artifact?.let { reflectionStore.load(it.hash) }
        _state.value = RevealState(
            artifact = artifact,
            reflection = reflection,
            privacyReminder = if (artifact?.isComplete == false) PrivacyMessages.FragmentReminder else PrivacyMessages.RevealReminder,
            canAskAnky = artifact != null && reflection == null && MirrorEligibility.canAsk(artifact.text),
        )
    }

    fun askAnky() {
        val artifact = _state.value.artifact ?: return
        if (!MirrorEligibility.canAsk(artifact.text)) {
            _state.update { it.copy(error = MirrorEligibility.reason(artifact.text)) }
            return
        }
        viewModelScope.launch(Dispatchers.IO) {
            _state.update { it.copy(isAsking = true, error = null) }
            runCatching {
                val identity = identityStore.loadOrCreate()
                val payload = mirrorClientProvider().askAnky(artifact.text.toByteArray(Charsets.UTF_8), identity)
                val reflection = LocalReflection(
                    hash = payload.hash,
                    title = payload.title,
                    reflection = payload.reflection,
                    createdAt = Instant.now(),
                    creditsRemaining = payload.creditsRemaining,
                )
                reflectionStore.save(reflection)
                indexStore.updateReflection(payload.hash, payload.title)
                reflection
            }.onSuccess { reflection ->
                _state.update {
                    it.copy(
                        reflection = reflection,
                        canAskAnky = false,
                        isAsking = false,
                    )
                }
            }.onFailure { error ->
                _state.update {
                    it.copy(
                        isAsking = false,
                        error = error.message ?: "Anky could not return a reflection right now.",
                    )
                }
            }
        }
    }
}
