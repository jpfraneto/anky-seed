package inc.anky.android.feature.reveal

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import inc.anky.android.BuildConfig
import inc.anky.android.core.credits.CreditsClient
import inc.anky.android.core.credits.NoopReflectionCreditCache
import inc.anky.android.core.credits.ReflectionCreditCache
import inc.anky.android.core.identity.WriterIdentity
import inc.anky.android.core.identity.WriterIdentityStore
import inc.anky.android.core.mirror.AnkyReflectionPrompt
import inc.anky.android.core.mirror.MirrorClient
import inc.anky.android.core.mirror.MirrorClientError
import inc.anky.android.core.mirror.MirrorErrorCode
import inc.anky.android.core.mirror.MirrorEligibility
import inc.anky.android.core.privacy.PrivacyMessages
import inc.anky.android.core.protocol.AnkyDuration
import inc.anky.android.core.storage.LocalAnkyArchive
import inc.anky.android.core.storage.LocalReflection
import inc.anky.android.core.storage.ReflectionRequestStore
import inc.anky.android.core.storage.ReflectionStore
import inc.anky.android.core.storage.SavedAnky
import inc.anky.android.core.storage.SessionIndexStore
import inc.anky.android.core.subscription.EntitlementGates
import java.time.Instant
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class RevealState(
    val artifact: SavedAnky? = null,
    val reflection: LocalReflection? = null,
    val privacyReminder: String = PrivacyMessages.RevealReminder,
    /** Entitlement truth at last refresh — subscription era, fail closed. */
    val entitled: Boolean = false,
    val canAskAnky: Boolean = false,
    val isAsking: Boolean = false,
    val isDeleting: Boolean = false,
    val isDeleted: Boolean = false,
    val copiedSection: RevealCopySection? = null,
    val reflectionStatusMessage: String = "",
    val streamingReflectionMarkdown: String = "",
    val progressStage: String? = null,
    val shouldRequestReviewAfterReadingFirstReflection: Boolean = false,
    val error: String? = null,
) {
    val streamingReflectionCharacterCount: Int
        get() = streamingReflectionMarkdown.length

    /**
     * Phase-3 §3: where the reflection would bloom for a free writer, the
     * veil — the same card, misted, one tap from the paywall. No LLM call
     * is ever made while this is true.
     */
    val reflectionVeiled: Boolean
        get() = artifact?.isComplete == true &&
            reflection == null &&
            EntitlementGates.freeSessionSkipsLlmReflection(entitled)

    val canSubmitReflectionRequest: Boolean
        get() = canAskAnky && !isAsking

    val canContinueWriting: Boolean
        get() = artifact?.isComplete == false

    val remainingWritingTime: String
        get() = countdownClock(maxOf(0, AnkyDuration.CompleteRitualMs - (artifact?.durationMs ?: 0L)))
}

enum class RevealCopySection {
    Writing,
    Reflection,
    ReflectionPrompt,
}

class RevealViewModel(
    private val hash: String,
    private val archive: LocalAnkyArchive,
    private val reflectionStore: ReflectionStore,
    private val requestStore: ReflectionRequestStore? = null,
    private val indexStore: SessionIndexStore,
    private val identityProvider: () -> WriterIdentity,
    private val mirrorClientProvider: () -> MirrorClient,
    // Credits-era parameters, kept as deprecated inert stubs because
    // AnkyApp.kt still passes them by name. The integrator deletes them
    // together with `core/credits` (WIRING-subscription.md checklist).
    @Suppress("UNUSED_PARAMETER") creditsClient: CreditsClient? = null,
    @Suppress("UNUSED_PARAMETER") reflectionCreditCache: ReflectionCreditCache = NoopReflectionCreditCache,
    @Suppress("UNUSED_PARAMETER") hasClaimedFreeCreditsProvider: () -> Boolean = { false },
    @Suppress("UNUSED_PARAMETER") markFreeCreditsClaimed: () -> Unit = {},
    /**
     * Entitlement gate — wire to `EntitlementStore.isEntitledForGating`
     * (or `lastKnownEntitledForGating` outside the store graph). Fails
     * closed: unwired means veiled, never a free LLM call.
     */
    private val entitledForGatingProvider: () -> Boolean = { false },
    /** Persisted "review already requested" flag (iOS UserDefaults key `anky.didRequestReviewAfterFirstReflection`). */
    private val didRequestFirstReflectionReviewProvider: () -> Boolean = { false },
    private val persistFirstReflectionReviewRequested: () -> Unit = {},
    private val dispatcher: CoroutineDispatcher = Dispatchers.IO,
) : ViewModel() {
    constructor(
        hash: String,
        archive: LocalAnkyArchive,
        reflectionStore: ReflectionStore,
        requestStore: ReflectionRequestStore? = null,
        indexStore: SessionIndexStore,
        identityStore: WriterIdentityStore,
        mirrorClientProvider: () -> MirrorClient,
        creditsClient: CreditsClient? = null,
        reflectionCreditCache: ReflectionCreditCache = NoopReflectionCreditCache,
        hasClaimedFreeCreditsProvider: () -> Boolean = { false },
        markFreeCreditsClaimed: () -> Unit = {},
        entitledForGatingProvider: () -> Boolean = { false },
        didRequestFirstReflectionReviewProvider: () -> Boolean = { false },
        persistFirstReflectionReviewRequested: () -> Unit = {},
    ) : this(
        hash = hash,
        archive = archive,
        reflectionStore = reflectionStore,
        requestStore = requestStore,
        indexStore = indexStore,
        identityProvider = { identityStore.loadOrCreate() },
        mirrorClientProvider = mirrorClientProvider,
        creditsClient = creditsClient,
        reflectionCreditCache = reflectionCreditCache,
        hasClaimedFreeCreditsProvider = hasClaimedFreeCreditsProvider,
        markFreeCreditsClaimed = markFreeCreditsClaimed,
        entitledForGatingProvider = entitledForGatingProvider,
        didRequestFirstReflectionReviewProvider = didRequestFirstReflectionReviewProvider,
        persistFirstReflectionReviewRequested = persistFirstReflectionReviewRequested,
    )

    private val _state = MutableStateFlow(RevealState())
    val state: StateFlow<RevealState> = _state
    private var reflectionWatcherJob: Job? = null
    private var reflectionRetryJob: Job? = null
    private var reflectionRetryStartedAtMs: Long? = null
    private val reflectionRetryLimitMs = 120_000L

    init {
        load()
    }

    fun load() {
        val artifact = runCatching { archive.load(hash) }.getOrNull()
        val reflection = artifact?.let { reflectionStore.load(it.hash) }
        val entitled = entitledForGatingProvider()
        val canAskAnky = artifact != null && entitled && MirrorEligibility.canAsk(
            isComplete = artifact.isComplete,
            hasReflection = reflection != null,
        )
        val isPending = canAskAnky && reflection == null && requestStore?.isPending(artifact!!.hash) == true
        _state.value = RevealState(
            artifact = artifact,
            reflection = reflection,
            privacyReminder = if (artifact?.isComplete == false) PrivacyMessages.FragmentReminder else PrivacyMessages.RevealReminder,
            entitled = entitled,
            canAskAnky = canAskAnky,
            isAsking = isPending,
            reflectionStatusMessage = if (isPending) "i am waiting with the mirror." else "",
            shouldRequestReviewAfterReadingFirstReflection = shouldRequestReview(reflection),
        )
        if (isPending) {
            if (reflectionRetryStartedAtMs == null) reflectionRetryStartedAtMs = System.currentTimeMillis()
            startPendingReflectionWatcher()
            schedulePendingReflectionRetry()
        }
    }

    /**
     * Re-reads entitlement truth (screen appear / resume) so a mid-session
     * purchase lifts the veil without recreating the screen — iOS re-checks
     * `entitlements.isEntitledForGating` on every render.
     */
    fun refreshEntitlement() {
        val entitled = entitledForGatingProvider()
        _state.update { current ->
            val artifact = current.artifact
            current.copy(
                entitled = entitled,
                canAskAnky = artifact != null && entitled && MirrorEligibility.canAsk(
                    isComplete = artifact.isComplete,
                    hasReflection = current.reflection != null,
                ),
            )
        }
    }

    fun askAnky() {
        submitReflectionRequest(allowWhileAsking = false)
    }

    private fun submitReflectionRequest(allowWhileAsking: Boolean) {
        val current = _state.value
        val artifact = current.artifact ?: return
        // Free sessions never ask the mirror — the veil already stands
        // where the reflection would appear.
        if (!current.entitled || !current.canAskAnky) return
        if (!allowWhileAsking && !current.canSubmitReflectionRequest) return
        _state.update {
            it.copy(
                isAsking = true,
                error = null,
                reflectionStatusMessage = "i am opening a quiet channel.",
                streamingReflectionMarkdown = "",
                progressStage = "stream_open",
            )
        }
        if (reflectionRetryStartedAtMs == null) reflectionRetryStartedAtMs = System.currentTimeMillis()
        requestStore?.markPending(artifact.hash)
        startPendingReflectionWatcher()
        viewModelScope.launch(dispatcher) {
            runCatching {
                _state.update { it.copy(reflectionStatusMessage = "i found your writer key. staying close.") }
                val identity = identityProvider()
                _state.update { it.copy(reflectionStatusMessage = "i am carrying the thread to the mirror.") }
                val payload = mirrorClientProvider().askAnky(
                    artifact.text.toByteArray(Charsets.UTF_8),
                    identity,
                    appVersion = "${BuildConfig.VERSION_NAME}(${BuildConfig.VERSION_CODE})",
                    progress = { event ->
                        _state.update {
                            it.copy(
                                progressStage = event.stage,
                                reflectionStatusMessage = progressMessage(event.stage, event.message),
                            )
                        }
                    },
                    reflectionChunk = { event ->
                        _state.update {
                            it.copy(
                                streamingReflectionMarkdown = it.streamingReflectionMarkdown + event.chunk,
                                reflectionStatusMessage = "writing the reflection... ${event.generatedCharacters} characters",
                            )
                        }
                    },
                )
                _state.update { it.copy(reflectionStatusMessage = "something answered. i am threading it back.") }
                if (payload.hash != artifact.hash) throw MirrorClientError.HashMismatch
                val reflection = LocalReflection(
                    hash = payload.hash,
                    title = payload.title,
                    reflection = payload.reflection,
                    createdAt = Instant.now(),
                    creditsRemaining = null,
                    tags = payload.tags,
                )
                reflectionStore.save(reflection)
                indexStore.updateReflection(payload.hash, payload.title, payload.tags)
                requestStore?.clear(payload.hash)
                reflection
            }.onSuccess { reflection ->
                reflectionWatcherJob?.cancel()
                reflectionRetryJob?.cancel()
                reflectionRetryStartedAtMs = null
                _state.update {
                    it.copy(
                        reflection = reflection,
                        canAskAnky = false,
                        isAsking = false,
                        reflectionStatusMessage = "",
                        streamingReflectionMarkdown = "",
                        progressStage = null,
                        shouldRequestReviewAfterReadingFirstReflection = shouldRequestReview(reflection),
                    )
                }
            }.onFailure { error ->
                val message = mirrorFailureMessage(error)
                if (message.contains("already being reflected", ignoreCase = true)) {
                    requestStore?.markPending(artifact.hash)
                    _state.update {
                        it.copy(
                            isAsking = true,
                            reflectionStatusMessage = "the mirror is already holding this thread.",
                            streamingReflectionMarkdown = "",
                            progressStage = null,
                            error = null,
                        )
                    }
                    startPendingReflectionWatcher()
                    schedulePendingReflectionRetry()
                    return@onFailure
                }
                requestStore?.clear(artifact.hash)
                reflectionWatcherJob?.cancel()
                reflectionRetryJob?.cancel()
                reflectionRetryStartedAtMs = null
                if (isEntitlementDenied(error)) {
                    // Server truth beats stale local truth: a 402 means the
                    // subscription lapsed — drop back behind the veil, no
                    // scolding error text.
                    _state.update {
                        it.copy(
                            entitled = false,
                            canAskAnky = false,
                            isAsking = false,
                            reflectionStatusMessage = "",
                            streamingReflectionMarkdown = "",
                            progressStage = null,
                            error = null,
                        )
                    }
                    return@onFailure
                }
                _state.update {
                    it.copy(
                        isAsking = false,
                        reflectionStatusMessage = "",
                        streamingReflectionMarkdown = "",
                        progressStage = null,
                        error = message,
                    )
                }
            }
        }
    }

    fun textForCopy(section: RevealCopySection): String? {
        val current = _state.value
        return when (section) {
            RevealCopySection.Writing -> current.artifact?.reconstructedText
            RevealCopySection.Reflection -> current.reflection?.let { reflection ->
                "${reflection.title}\n\n${reflection.reflection}"
            }
            RevealCopySection.ReflectionPrompt -> current.artifact
                ?.takeIf { it.isComplete }
                ?.let { AnkyReflectionPrompt.build(it.reconstructedText) }
        }?.takeIf { it.isNotBlank() }
    }

    fun markCopied(section: RevealCopySection) {
        _state.update { it.copy(copiedSection = section) }
    }

    fun clearCopied(section: RevealCopySection) {
        _state.update { current ->
            if (current.copiedSection == section) current.copy(copiedSection = null) else current
        }
    }

    fun markFirstReflectionReviewRequested() {
        persistFirstReflectionReviewRequested()
        _state.update { it.copy(shouldRequestReviewAfterReadingFirstReflection = false) }
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
                runCatching { requestStore?.clear(artifact.hash) }
                indexStore.delete(artifact.hash)
            }.onSuccess {
                reflectionWatcherJob?.cancel()
                reflectionRetryJob?.cancel()
                reflectionRetryStartedAtMs = null
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

    private fun shouldRequestReview(reflection: LocalReflection?): Boolean =
        reflection != null &&
            !didRequestFirstReflectionReviewProvider() &&
            runCatching { reflectionStore.list().size }.getOrDefault(0) == 1

    private fun refreshLocalReflection() {
        val current = _state.value
        val artifact = current.artifact ?: return
        if (current.reflection != null) return

        val savedReflection = reflectionStore.load(artifact.hash)
        if (savedReflection != null) {
            requestStore?.clear(artifact.hash)
            reflectionWatcherJob?.cancel()
            reflectionRetryJob?.cancel()
            reflectionRetryStartedAtMs = null
            _state.update {
                it.copy(
                    reflection = savedReflection,
                    canAskAnky = false,
                    isAsking = false,
                    reflectionStatusMessage = "",
                    streamingReflectionMarkdown = "",
                    progressStage = null,
                    shouldRequestReviewAfterReadingFirstReflection = shouldRequestReview(savedReflection),
                    error = null,
                )
            }
        } else if (requestStore?.isPending(artifact.hash) == true) {
            _state.update {
                it.copy(
                    isAsking = true,
                    reflectionStatusMessage = it.reflectionStatusMessage.ifBlank { "i am waiting with the mirror." },
                )
            }
        } else if (current.isAsking) {
            _state.update {
                it.copy(
                    isAsking = false,
                    reflectionStatusMessage = "",
                    streamingReflectionMarkdown = "",
                    progressStage = null,
                )
            }
        }
    }

    private fun startPendingReflectionWatcher() {
        if (reflectionWatcherJob?.isActive == true) return
        reflectionWatcherJob = viewModelScope.launch(dispatcher) {
            while (true) {
                delay(1_000)
                refreshLocalReflection()
            }
        }
    }

    private fun schedulePendingReflectionRetry() {
        val artifact = _state.value.artifact ?: return
        if (_state.value.reflection != null) return
        if (reflectionRetryJob?.isActive == true) return
        val startedAt = reflectionRetryStartedAtMs ?: System.currentTimeMillis().also { reflectionRetryStartedAtMs = it }
        if (System.currentTimeMillis() - startedAt >= reflectionRetryLimitMs) {
            requestStore?.clear(artifact.hash)
            reflectionRetryStartedAtMs = null
            _state.update {
                it.copy(
                    isAsking = false,
                    reflectionStatusMessage = "",
                    error = GenericMirrorFailureMessage,
                )
            }
            return
        }

        reflectionRetryJob = viewModelScope.launch(dispatcher) {
            delay(3_000)
            reflectionRetryJob = null
            retryPendingReflectionIfNeeded()
        }
    }

    private fun retryPendingReflectionIfNeeded() {
        refreshLocalReflection()
        val current = _state.value
        val artifact = current.artifact ?: return
        if (current.reflection != null) return
        if (requestStore?.isPending(artifact.hash) != true) return
        if (!current.entitled) return
        if (!MirrorEligibility.canAsk(isComplete = artifact.isComplete, hasReflection = false)) return
        submitReflectionRequest(allowWhileAsking = true)
    }
}

internal fun progressMessage(stage: String?, fallback: String? = null): String =
    when (stage) {
        "stream_open" -> "opening the mirror..."
        "request_received" -> "received your writing..."
        "dot_anky_read" -> "reading your .anky..."
        "hash_computed" -> "preparing your writing..."
        "identity_verified" -> "opening the way..."
        "protocol_validated" -> "validating the ritual..."
        "reflection_prepared" -> "preparing the reflection..."
        "provider_started" -> "anky is writing..."
        "provider_finished" -> "bringing it back..."
        "complete" -> "opening the scroll..."
        else -> fallback ?: "anky is working..."
    }

private fun mirrorFailureMessage(error: Throwable): String =
    when (error) {
        is MirrorClientError -> error.message ?: GenericMirrorFailureMessage
        else -> GenericMirrorFailureMessage
    }

/**
 * The server refusing for lack of entitlement — today the backend still
 * answers 402 `INSUFFICIENT_CREDITS` (MirrorClient maps that code); once it
 * speaks `ENTITLEMENT_REQUIRED` the raw code reaches us as
 * [MirrorErrorCode.Unknown] until core/mirror learns it, so the message is
 * also sniffed here. Both roads lead to the same veil, never an error toast.
 */
internal fun isEntitlementDenied(error: Throwable): Boolean {
    if (error !is MirrorClientError.Server) return false
    if (error.code == MirrorErrorCode.InsufficientCredits ||
        error.code == MirrorErrorCode.TrialAlreadyClaimed
    ) {
        return true
    }
    val message = error.message.orEmpty()
    return message.contains("ENTITLEMENT_REQUIRED", ignoreCase = true) ||
        message.contains("entitlement", ignoreCase = true) ||
        message.contains("subscription", ignoreCase = true)
}

private const val GenericMirrorFailureMessage = "Anky could not return a reflection right now."

private fun countdownClock(durationMs: Long): String {
    val totalSeconds = maxOf(0, durationMs / 1000)
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return "${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}"
}
