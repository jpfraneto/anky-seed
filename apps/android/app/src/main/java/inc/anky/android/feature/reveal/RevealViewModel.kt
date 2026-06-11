package inc.anky.android.feature.reveal

import android.app.Activity
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import inc.anky.android.BuildConfig
import inc.anky.android.core.credits.CreditPackage
import inc.anky.android.core.credits.CreditState
import inc.anky.android.core.credits.CreditsClient
import inc.anky.android.core.credits.NoopReflectionCreditCache
import inc.anky.android.core.credits.ReflectionCreditCache
import inc.anky.android.core.identity.WriterIdentityStore
import inc.anky.android.core.identity.WriterIdentity
import inc.anky.android.core.mirror.AnkyReflectionPrompt
import inc.anky.android.core.mirror.MirrorClient
import inc.anky.android.core.mirror.MirrorClientError
import inc.anky.android.core.mirror.MirrorErrorCode
import inc.anky.android.core.mirror.MirrorEligibility
import inc.anky.android.core.mirror.ReflectionCreditPresentation
import inc.anky.android.core.mirror.ReflectionCreditPromptState
import inc.anky.android.core.privacy.PrivacyMessages
import inc.anky.android.core.protocol.AnkyDuration
import inc.anky.android.core.storage.LocalAnkyArchive
import inc.anky.android.core.storage.LocalReflection
import inc.anky.android.core.storage.ReflectionRequestStore
import inc.anky.android.core.storage.ReflectionStore
import inc.anky.android.core.storage.SavedAnky
import inc.anky.android.core.storage.SessionIndexStore
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
    val canAskAnky: Boolean = false,
    val isAsking: Boolean = false,
    val isDeleting: Boolean = false,
    val isDeleted: Boolean = false,
    val copiedSection: RevealCopySection? = null,
    val creditBalance: Int? = null,
    val creditPackages: List<CreditPackage> = emptyList(),
    val creditsLoading: Boolean = false,
    val purchasingCreditPackageId: String? = null,
    val hasClaimedFreeCredits: Boolean = false,
    val creditsDenied: Boolean = false,
    val reflectionStatusMessage: String = "",
    val streamingReflectionMarkdown: String = "",
    val progressStage: String? = null,
    val error: String? = null,
) {
    val streamingReflectionCharacterCount: Int
        get() = streamingReflectionMarkdown.length

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

    val needsCreditsToReflect: Boolean
        get() = artifact?.isComplete == true &&
            reflection == null &&
            !isAsking &&
            creditPromptState == ReflectionCreditPromptState.Unavailable

    val shouldShowCreditsLink: Boolean
        get() = creditPromptState == ReflectionCreditPromptState.Unavailable

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
    private val creditsClient: CreditsClient? = null,
    private val reflectionCreditCache: ReflectionCreditCache = NoopReflectionCreditCache,
    private val hasClaimedFreeCreditsProvider: () -> Boolean = { false },
    private val markFreeCreditsClaimed: () -> Unit = {},
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
        val cachedBalance = cachedCreditBalance()
        val canAskAnky = artifact != null && MirrorEligibility.canAsk(
            isComplete = artifact.isComplete,
            hasReflection = reflection != null,
        )
        val isPending = artifact != null && reflection == null && requestStore?.isPending(artifact.hash) == true
        _state.value = RevealState(
            artifact = artifact,
            reflection = reflection,
            privacyReminder = if (artifact?.isComplete == false) PrivacyMessages.FragmentReminder else PrivacyMessages.RevealReminder,
            canAskAnky = canAskAnky,
            isAsking = isPending,
            reflectionStatusMessage = if (isPending) "i am waiting with the mirror." else "",
            creditBalance = reflection?.creditsRemaining ?: cachedBalance,
            hasClaimedFreeCredits = hasClaimedFreeCreditsProvider() || reflectionStore.list().isNotEmpty(),
        )
        if (isPending) {
            if (reflectionRetryStartedAtMs == null) reflectionRetryStartedAtMs = System.currentTimeMillis()
            startPendingReflectionWatcher()
            schedulePendingReflectionRetry()
        }
    }

    fun askAnky() {
        submitReflectionRequest(allowWhileAsking = false)
    }

    private fun submitReflectionRequest(allowWhileAsking: Boolean) {
        val current = _state.value
        val artifact = current.artifact ?: return
        if (!allowWhileAsking && !current.canSubmitReflectionRequest) return
        if (allowWhileAsking && current.creditPromptState == ReflectionCreditPromptState.Unavailable) return
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
                    creditsRemaining = payload.creditsRemaining,
                    tags = payload.tags,
                )
                reflectionStore.save(reflection)
                indexStore.updateReflection(payload.hash, payload.title, payload.tags)
                requestStore?.clear(payload.hash)
                if (payload.creditsRemaining != null) {
                    reflectionCreditCache.storeBalance(payload.creditsRemaining, identity.accountId)
                    creditsClient?.invalidateCreditBalanceCache()
                }
                markFreeCreditsClaimed()
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
                        creditBalance = reflection.creditsRemaining ?: it.creditBalance,
                        hasClaimedFreeCredits = true,
                        creditsDenied = false,
                    )
                }
            }.onFailure { error ->
                val message = mirrorFailureMessage(error)
                val creditDenied = isCreditDenied(error, message)
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
                if (creditDenied) markCreditAccessDenied()
                _state.update {
                    it.copy(
                        isAsking = false,
                        reflectionStatusMessage = "",
                        streamingReflectionMarkdown = "",
                        progressStage = null,
                        creditBalance = if (creditDenied) 0 else it.creditBalance,
                        hasClaimedFreeCredits = if (creditDenied) true else it.hasClaimedFreeCredits,
                        creditsDenied = it.creditsDenied || creditDenied,
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

    fun refreshCredits(showError: Boolean = true) {
        refreshLocalReflection()
        val current = _state.value
        if (!current.canAskAnky || creditsClient == null) return

        _state.update { it.copy(creditsLoading = true) }
        viewModelScope.launch(dispatcher) {
            runCatching {
                val identity = identityProvider()
                creditsClient.configure(identity.accountId)
                identity.accountId to creditsClient.refresh()
            }.onSuccess { (accountId, refreshedCreditState) ->
                val creditState = refreshedCreditState.afterDeviceGiftDenialGate(
                    cachedBalance = reflectionCreditCache.balance(accountId),
                    hasClaimedFreeCredits = reflectionCreditCache.hasClaimedFreeCredits(accountId),
                )
                reflectionCreditCache.storeBalance(creditState.balance, accountId)
                _state.update {
                    it.copy(
                        creditBalance = creditState.balance,
                        creditPackages = creditState.packages,
                        hasClaimedFreeCredits = it.hasClaimedFreeCredits ||
                            reflectionCreditCache.hasClaimedFreeCredits(accountId),
                        creditsDenied = it.creditsDenied && creditState.balance == 0,
                        creditsLoading = false,
                        error = if (showError) null else it.error,
                    )
                }
            }.onFailure {
                _state.update {
                    it.copy(
                        creditsLoading = false,
                        error = if (showError) "Could not load reflections." else it.error,
                    )
                }
            }
        }
    }

    fun purchaseCredits(packageId: String, activity: Activity?) {
        val current = _state.value
        if (current.purchasingCreditPackageId != null || creditsClient == null) return
        _state.update {
            it.copy(
                purchasingCreditPackageId = packageId,
                creditsLoading = true,
                error = null,
            )
        }
        viewModelScope.launch(dispatcher) {
            try {
                val identity = identityProvider()
                creditsClient.configure(identity.accountId)
                val refreshed = creditsClient.purchase(packageId, activity)
                val normalizedCreditState = refreshed.afterDeviceGiftDenialGate(
                    cachedBalance = reflectionCreditCache.balance(identity.accountId),
                    hasClaimedFreeCredits = reflectionCreditCache.hasClaimedFreeCredits(identity.accountId),
                )
                reflectionCreditCache.storeBalance(normalizedCreditState.balance, identity.accountId)
                _state.update {
                    it.copy(
                        creditBalance = normalizedCreditState.balance,
                        creditPackages = normalizedCreditState.packages,
                        hasClaimedFreeCredits = it.hasClaimedFreeCredits ||
                            reflectionCreditCache.hasClaimedFreeCredits(identity.accountId),
                        creditsDenied = it.creditsDenied && normalizedCreditState.balance == 0,
                        creditsLoading = false,
                        purchasingCreditPackageId = null,
                        error = if (refreshed.message == "Could not complete that credit purchase.") refreshed.message else null,
                    )
                }
            } catch (_: Throwable) {
                _state.update {
                    it.copy(
                        creditsLoading = false,
                        purchasingCreditPackageId = null,
                        error = "Could not complete that credit purchase.",
                    )
                }
            }
        }
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

    private fun refreshLocalReflection() {
        val current = _state.value
        val artifact = current.artifact ?: return
        if (current.reflection != null) return

        val savedReflection = reflectionStore.load(artifact.hash)
        if (savedReflection != null) {
            savedReflection.creditsRemaining?.takeIf { reflectionCreditCache !== NoopReflectionCreditCache }?.let {
                val accountId = runCatching { identityProvider().accountId }.getOrNull()
                if (accountId != null) reflectionCreditCache.storeBalance(it, accountId)
            }
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
                    creditBalance = savedReflection.creditsRemaining ?: it.creditBalance,
                    hasClaimedFreeCredits = true,
                    creditsDenied = false,
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

    private fun cachedCreditBalance(): Int? =
        if (reflectionCreditCache === NoopReflectionCreditCache) {
            null
        } else {
            runCatching { reflectionCreditCache.balance(identityProvider().accountId) }.getOrNull()
        }

    private fun markCreditAccessDenied() {
        val accountId = runCatching { identityProvider().accountId }.getOrNull()
        if (accountId != null && reflectionCreditCache !== NoopReflectionCreditCache) {
            reflectionCreditCache.markFreeCreditsClaimed(accountId)
            reflectionCreditCache.storeBalance(0, accountId)
        }
        markFreeCreditsClaimed()
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
        "credit_checked" -> "checking reflection access..."
        "reflection_prepared" -> "preparing the reflection..."
        "provider_started" -> "anky is writing..."
        "provider_finished" -> "bringing it back..."
        "credit_spent" -> "settling..."
        "x402_quote_created" -> "checking payment options..."
        "x402_verified" -> "payment verified..."
        "x402_settled" -> "settling..."
        "credit_not_spent" -> "no credit spent..."
        "complete" -> "opening the scroll..."
        else -> fallback ?: "anky is working..."
    }

private fun mirrorFailureMessage(error: Throwable): String {
    if (error is MirrorClientError.Server && error.code == MirrorErrorCode.TrialAlreadyClaimed) {
        return "This device already used its first two reflections. Add credits to ask Anky again. Writing is still free."
    }
    if (isCreditDenied(error, error.message.orEmpty())) {
        return "You need one reflection credit to ask Anky. Writing is still free."
    }
    return when (error) {
        is MirrorClientError -> error.message ?: GenericMirrorFailureMessage
        else -> GenericMirrorFailureMessage
    }
}

private fun isCreditDenied(error: Throwable, message: String): Boolean {
    if (error is MirrorClientError.Server) {
        return error.code == MirrorErrorCode.InsufficientCredits ||
            error.code == MirrorErrorCode.TrialAlreadyClaimed
    }
    return message.contains("credit", ignoreCase = true)
}

private const val GenericMirrorFailureMessage = "Anky could not return a reflection right now."

internal fun CreditState.afterDeviceGiftDenialGate(
    cachedBalance: Int?,
    hasClaimedFreeCredits: Boolean,
): CreditState =
    if (
        hasClaimedFreeCredits &&
        cachedBalance == 0 &&
        balance == ReflectionCreditPresentation.FirstGiftCount
    ) {
        copy(balance = 0)
    } else {
        this
    }

private fun countdownClock(durationMs: Long): String {
    val totalSeconds = maxOf(0, durationMs / 1000)
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return "${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}"
}
