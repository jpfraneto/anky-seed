package inc.anky.android.feature.reveal

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import inc.anky.android.BuildConfig
import inc.anky.android.core.identity.WriterIdentityStore
import inc.anky.android.core.identity.WriterIdentity
import inc.anky.android.core.mirror.MirrorClient
import inc.anky.android.core.mirror.MirrorClientError
import inc.anky.android.core.mirror.MirrorEligibility
import inc.anky.android.core.privacy.PrivacyMessages
import inc.anky.android.core.storage.LocalAnkyArchive
import inc.anky.android.core.storage.LocalReflection
import inc.anky.android.core.storage.ReflectionStore
import inc.anky.android.core.storage.SavedAnky
import inc.anky.android.core.storage.SessionIndexStore
import java.time.Instant
import kotlinx.coroutines.CoroutineDispatcher
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
    val didCopyText: Boolean = false,
    val error: String? = null,
)

class RevealViewModel(
    private val hash: String,
    private val archive: LocalAnkyArchive,
    private val reflectionStore: ReflectionStore,
    private val indexStore: SessionIndexStore,
    private val identityProvider: () -> WriterIdentity,
    private val mirrorClientProvider: () -> MirrorClient,
    private val dispatcher: CoroutineDispatcher = Dispatchers.IO,
) : ViewModel() {
    constructor(
        hash: String,
        archive: LocalAnkyArchive,
        reflectionStore: ReflectionStore,
        indexStore: SessionIndexStore,
        identityStore: WriterIdentityStore,
        mirrorClientProvider: () -> MirrorClient,
    ) : this(
        hash = hash,
        archive = archive,
        reflectionStore = reflectionStore,
        indexStore = indexStore,
        identityProvider = { identityStore.loadOrCreate() },
        mirrorClientProvider = mirrorClientProvider,
    )

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
            canAskAnky = artifact != null && MirrorEligibility.canAsk(
                isComplete = artifact.isComplete,
                hasReflection = reflection != null,
            ),
        )
    }

    fun askAnky() {
        val current = _state.value
        val artifact = current.artifact ?: return
        if (!current.canAskAnky || current.isAsking) return
        _state.update { it.copy(isAsking = true, error = null) }
        viewModelScope.launch(dispatcher) {
            runCatching {
                val identity = identityProvider()
                val payload = mirrorClientProvider().askAnky(
                    artifact.text.toByteArray(Charsets.UTF_8),
                    identity,
                    appVersion = "${BuildConfig.VERSION_NAME}(${BuildConfig.VERSION_CODE})",
                )
                if (payload.hash != artifact.hash) throw MirrorClientError.HashMismatch
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
                        error = mirrorFailureMessage(error),
                    )
                }
            }
        }
    }

    fun markTextCopied() {
        _state.update { it.copy(didCopyText = true) }
    }
}

private fun mirrorFailureMessage(error: Throwable): String =
    when (error) {
        is MirrorClientError -> error.message ?: GenericMirrorFailureMessage
        else -> GenericMirrorFailureMessage
    }

private const val GenericMirrorFailureMessage = "Anky could not return a reflection right now."
