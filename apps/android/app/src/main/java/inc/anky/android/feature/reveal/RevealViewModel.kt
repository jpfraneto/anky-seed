package inc.anky.android.feature.reveal

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import inc.anky.android.BuildConfig
import inc.anky.android.core.identity.WriterIdentityStore
import inc.anky.android.core.identity.WriterIdentity
import inc.anky.android.core.mirror.MirrorClient
import inc.anky.android.core.mirror.MirrorClientError
import inc.anky.android.core.mirror.MirrorEligibility
import inc.anky.android.core.mirror.ReflectionCreditPresentation
import inc.anky.android.core.mirror.ReflectionCreditPromptState
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
    val isDeleting: Boolean = false,
    val isDeleted: Boolean = false,
    val didCopyText: Boolean = false,
    val creditBalance: Int? = null,
    val creditsLoading: Boolean = false,
    val hasClaimedFreeCredits: Boolean = false,
    val creditsDenied: Boolean = false,
    val reflectionStatusMessage: String = "",
    val error: String? = null,
) {
    val creditPromptState: ReflectionCreditPromptState
        get() = ReflectionCreditPresentation.state(
            creditsRemaining = creditBalance,
            hasClaimedFreeCredits = hasClaimedFreeCredits,
            creditsDenied = creditsDenied,
        )

    val creditPromptMessage: String
        get() = ReflectionCreditPresentation.messageFor(creditPromptState)

    val canSubmitReflectionRequest: Boolean
        get() = canAskAnky && !isAsking && creditPromptState != ReflectionCreditPromptState.Unavailable

    val shouldShowCreditsLink: Boolean
        get() = creditPromptState == ReflectionCreditPromptState.Unavailable
}

class RevealViewModel(
    private val hash: String,
    private val archive: LocalAnkyArchive,
    private val reflectionStore: ReflectionStore,
    private val indexStore: SessionIndexStore,
    private val identityProvider: () -> WriterIdentity,
    private val mirrorClientProvider: () -> MirrorClient,
    private val hasClaimedFreeCreditsProvider: () -> Boolean = { false },
    private val markFreeCreditsClaimed: () -> Unit = {},
    private val dispatcher: CoroutineDispatcher = Dispatchers.IO,
) : ViewModel() {
    constructor(
        hash: String,
        archive: LocalAnkyArchive,
        reflectionStore: ReflectionStore,
        indexStore: SessionIndexStore,
        identityStore: WriterIdentityStore,
        mirrorClientProvider: () -> MirrorClient,
        hasClaimedFreeCreditsProvider: () -> Boolean = { false },
        markFreeCreditsClaimed: () -> Unit = {},
    ) : this(
        hash = hash,
        archive = archive,
        reflectionStore = reflectionStore,
        indexStore = indexStore,
        identityProvider = { identityStore.loadOrCreate() },
        mirrorClientProvider = mirrorClientProvider,
        hasClaimedFreeCreditsProvider = hasClaimedFreeCreditsProvider,
        markFreeCreditsClaimed = markFreeCreditsClaimed,
    )

    private val _state = MutableStateFlow(RevealState())
    val state: StateFlow<RevealState> = _state

    init {
        load()
    }

    fun load() {
        val artifact = runCatching { archive.load(hash) }.getOrNull()
        val reflection = artifact?.let { reflectionStore.load(it.hash) }
        val canAskAnky = artifact != null && MirrorEligibility.canAsk(
            isComplete = artifact.isComplete,
            hasReflection = reflection != null,
        )
        _state.value = RevealState(
            artifact = artifact,
            reflection = reflection,
            privacyReminder = if (artifact?.isComplete == false) PrivacyMessages.FragmentReminder else PrivacyMessages.RevealReminder,
            canAskAnky = canAskAnky,
            hasClaimedFreeCredits = hasClaimedFreeCreditsProvider() || reflectionStore.list().isNotEmpty(),
        )
    }

    fun askAnky() {
        val current = _state.value
        val artifact = current.artifact ?: return
        if (!current.canSubmitReflectionRequest) return
        _state.update { it.copy(isAsking = true, error = null, reflectionStatusMessage = "i am opening a quiet channel.") }
        viewModelScope.launch(dispatcher) {
            runCatching {
                _state.update { it.copy(reflectionStatusMessage = "i found your writer key. staying close.") }
                val identity = identityProvider()
                _state.update { it.copy(reflectionStatusMessage = "i am carrying the thread to the mirror.") }
                val payload = mirrorClientProvider().askAnky(
                    artifact.text.toByteArray(Charsets.UTF_8),
                    identity,
                    appVersion = "${BuildConfig.VERSION_NAME}(${BuildConfig.VERSION_CODE})",
                )
                _state.update { it.copy(reflectionStatusMessage = "something answered. i am threading it back.") }
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
                markFreeCreditsClaimed()
                reflection
            }.onSuccess { reflection ->
                _state.update {
                    it.copy(
                        reflection = reflection,
                        canAskAnky = false,
                        isAsking = false,
                        reflectionStatusMessage = "",
                        creditBalance = reflection.creditsRemaining ?: it.creditBalance,
                        hasClaimedFreeCredits = true,
                        creditsDenied = false,
                    )
                }
            }.onFailure { error ->
                val message = mirrorFailureMessage(error)
                _state.update {
                    it.copy(
                        isAsking = false,
                        reflectionStatusMessage = "",
                        creditBalance = if (message.contains("credit", ignoreCase = true)) 0 else it.creditBalance,
                        creditsDenied = it.creditsDenied || message.contains("credit", ignoreCase = true),
                        error = message,
                    )
                }
            }
        }
    }

    fun markTextCopied() {
        _state.update { it.copy(didCopyText = true) }
    }

    fun deleteSession() {
        val current = _state.value
        val artifact = current.artifact ?: return
        if (current.isDeleting || current.isDeleted) return
        _state.update { it.copy(isDeleting = true, error = null) }
        viewModelScope.launch(dispatcher) {
            runCatching {
                archive.delete(artifact.hash)
                runCatching { reflectionStore.delete(artifact.hash) }
                indexStore.delete(artifact.hash)
            }.onSuccess {
                _state.update {
                    it.copy(
                        artifact = null,
                        reflection = null,
                        canAskAnky = false,
                        isDeleting = false,
                        isDeleted = true,
                    )
                }
            }.onFailure {
                _state.update {
                    it.copy(
                        isDeleting = false,
                        error = "This writing session could not be deleted.",
                    )
                }
            }
        }
    }
}

private fun mirrorFailureMessage(error: Throwable): String =
    when (error) {
        is MirrorClientError -> error.message ?: GenericMirrorFailureMessage
        else -> GenericMirrorFailureMessage
    }

private const val GenericMirrorFailureMessage = "Anky could not return a reflection right now."
