package inc.anky.android.feature.you

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import android.net.Uri
import inc.anky.android.BuildConfig
import inc.anky.android.app.UserSettingsStore
import inc.anky.android.core.credits.CreditState
import inc.anky.android.core.credits.CreditsClient
import inc.anky.android.core.credits.NoopReflectionCreditCache
import inc.anky.android.core.credits.ReflectionCreditCache
import inc.anky.android.core.credits.cachedCreditState
import inc.anky.android.core.identity.BiometricGate
import inc.anky.android.core.identity.WriterIdentityStore
import inc.anky.android.core.mirror.ReflectionCreditPresentation
import inc.anky.android.core.notifications.DailyReminderScheduler
import inc.anky.android.core.privacy.PrivacyMessages
import inc.anky.android.core.storage.ActiveDraftStore
import inc.anky.android.core.storage.AndroidEncryptedBackupError
import inc.anky.android.core.storage.AndroidEncryptedBackupException
import inc.anky.android.core.storage.AndroidEncryptedBackupStore
import inc.anky.android.core.storage.AppOpenStore
import inc.anky.android.core.storage.BackupImporter
import inc.anky.android.core.storage.BackupExporting
import inc.anky.android.core.storage.LocalAnkyArchive
import inc.anky.android.core.storage.ReflectionRequestStore
import inc.anky.android.core.storage.ReflectionStore
import inc.anky.android.core.storage.SessionIndexStore
import inc.anky.android.core.storage.SessionSummary
import inc.anky.android.core.subscription.AnkyPurchasesConfig
import inc.anky.android.core.subscription.EntitlementState
import inc.anky.android.core.subscription.EntitlementStore
import inc.anky.android.core.subscription.SubscriptionPriceFormatter
import java.io.File
import java.net.URLEncoder
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class YouState(
    val accountId: String = "",
    val recoveryPhrase: String? = null,
    val appLockEnabled: Boolean = false,
    val dailyReminderEnabled: Boolean = false,
    val dailyReminderMinutes: Int = 9 * 60,
    val mirrorBaseUrl: String = BuildConfig.DEFAULT_MIRROR_BASE_URL,
    /** RevenueCat entitlement truth — the only subscription state the UI reads. */
    val subscription: EntitlementState = EntitlementState(),
    /** False until an [EntitlementStore] is wired in; the row degrades gracefully. */
    val isSubscriptionTruthAvailable: Boolean = false,
    /** Deprecated credits-economy remnant: inert, kept only so pre-cleanup
     * callers and tests keep compiling. The cleanup phase deletes it. */
    val creditState: CreditState = CreditState(false, null, "no credit packs available"),
    /** Deprecated credits-economy remnant (cleanup phase deletes). */
    val hasClaimedFreeCredits: Boolean = false,
    /** Deprecated credits-economy remnant (cleanup phase deletes). */
    val purchasingCreditPackageId: String? = null,
    val isRestoringPurchases: Boolean = false,
    val exportedFile: File? = null,
    val formattedWritingExportFile: File? = null,
    val isEncryptedBackupEnabled: Boolean = false,
    val encryptedBackupLastDate: Instant? = null,
    val isEncryptedBackupWorking: Boolean = false,
    val localAnkyFileCount: Int = 0,
    val completeAnkyCount: Int = 0,
    val totalWritingMinutes: Int = 0,
    val currentStreak: Int = 0,
    val reflectionCount: Int = 0,
    val completeAnkySessions: List<SessionSummary> = emptyList(),
    val statusMessage: String? = null,
    val error: String? = null,
) {
    /** Deprecated credits-economy remnant (cleanup phase deletes). */
    val freeCreditMessage: String
        get() = PrivacyMessages.freeCreditMessage(accountId, "${BuildConfig.VERSION_NAME} ${BuildConfig.VERSION_CODE}")

    val supportFeedbackEmailUrl: String
        get() {
            val subject = mailtoQueryValue("Anky support / feedback")
            val body = mailtoQueryValue("account id: $accountId\n\n")
            return "mailto:support@anky.app?subject=$subject&body=$body"
        }

    val appVersion: String
        get() = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"

    /** Deprecated credits-economy remnant (cleanup phase deletes). */
    val presentedCreditBalance: Int?
        get() = creditState.balance

    /** Deprecated credits-economy remnant (cleanup phase deletes). */
    val hasUnspentGiftCredit: Boolean
        get() = false

    /** Deprecated credits-economy remnant (cleanup phase deletes). */
    val canPurchaseCredits: Boolean
        get() = true

    /** Deprecated credits-economy remnant (cleanup phase deletes). */
    val creditDetailTitle: String
        get() = creditState.balance?.toString() ?: "..."

    /** Deprecated credits-economy remnant (cleanup phase deletes). */
    val creditDetailCaption: String
        get() = "credits"
}

private fun mailtoQueryValue(value: String): String =
    URLEncoder.encode(value, Charsets.UTF_8.name()).replace("+", "%20")

class YouViewModel(
    private val identityStore: WriterIdentityStore,
    private val settingsStore: UserSettingsStore,
    private val reminderScheduler: DailyReminderScheduler,
    private val creditsClient: CreditsClient,
    private val reflectionCreditCache: ReflectionCreditCache = NoopReflectionCreditCache,
    private val exporter: BackupExporting,
    private val backupImporter: BackupImporter,
    private val activeDraftStore: ActiveDraftStore,
    private val archive: LocalAnkyArchive,
    private val reflectionStore: ReflectionStore,
    private val requestStore: ReflectionRequestStore,
    private val indexStore: SessionIndexStore,
    private val appOpenStore: AppOpenStore,
    private val encryptedBackupStore: AndroidEncryptedBackupStore,
    private val biometricGate: BiometricGate,
    private val entitlementStore: EntitlementStore? = null,
) : ViewModel() {
    private val _state = MutableStateFlow(YouState())
    private val creditState = MutableStateFlow(_state.value.creditState)
    private val accountIdState = MutableStateFlow(_state.value.accountId)
    val state: StateFlow<YouState> = _state

    init {
        viewModelScope.launch {
            val identity = runCatching {
                identityStore.loadOrCreate()
            }.getOrElse {
                _state.update(::localIdentityLoadFailureState)
                return@launch
            }
            accountIdState.value = identity.accountId
            cachedCreditState(reflectionCreditCache.balance(identity.accountId))?.let { creditState.value = it }
            combine(settingsStore.settings, creditState, accountIdState) { settings, credits, accountId ->
                val sessions = indexStore.rebuild(archive, reflectionStore)
                val encryptedBackupStatus = encryptedBackupStore.status()
                YouState(
                    accountId = accountId,
                    appLockEnabled = settings.appLockEnabled,
                    dailyReminderEnabled = settings.dailyReminderEnabled,
                    dailyReminderMinutes = settings.dailyReminderMinutes,
                    mirrorBaseUrl = settings.mirrorBaseUrl,
                    creditState = credits,
                    hasClaimedFreeCredits = reflectionCreditCache.hasClaimedFreeCredits(accountId),
                    isEncryptedBackupEnabled = encryptedBackupStatus.isEnabled,
                    encryptedBackupLastDate = encryptedBackupStatus.lastBackupDate,
                    localAnkyFileCount = sessions.size,
                    completeAnkyCount = sessions.count { it.isComplete },
                    totalWritingMinutes = totalWritingMinutes(sessions),
                    currentStreak = currentStreak(sessions.filter { it.isComplete }.map { it.createdAt }),
                    reflectionCount = localReflectionCount(),
                    completeAnkySessions = completeSessions(sessions),
                )
            }.collect { refreshed ->
                _state.update { previous -> mergeRefreshedYouState(previous, refreshed) }
            }
        }
        entitlementStore?.let { store ->
            viewModelScope.launch {
                store.state.collect { entitlement ->
                    _state.update {
                        it.copy(
                            subscription = entitlement,
                            isSubscriptionTruthAvailable = true,
                        )
                    }
                }
            }
            viewModelScope.launch {
                store.loadPackages()
            }
        }
    }

    fun revealRecoveryPhrase(
        authReason: String = YouStatusCopy.ShowRecoveryWordsReason,
        authFailure: String = YouStatusCopy.CouldNotConfirmIdentity,
    ) {
        viewModelScope.launch {
            if (!biometricGate.authenticate(authReason)) {
                _state.update { it.copy(error = authFailure) }
                return@launch
            }
            runCatching {
                identityStore.loadOrCreateRecoveryPhrase().text
            }.onSuccess { recoveryPhrase ->
                _state.update {
                    it.copy(
                        recoveryPhrase = recoveryPhrase,
                        error = null,
                    )
                }
            }.onFailure {
                _state.update { it.copy(error = YouStatusCopy.CouldNotLoadRecoveryPhrase) }
            }
        }
    }

    fun hideRecoveryPhrase() {
        _state.update { it.copy(recoveryPhrase = null) }
    }

    fun backUpIdentityToDeviceSecureStorage(
        authReason: String = YouStatusCopy.BackUpRecoveryWordsReason,
        authFailure: String = YouStatusCopy.CouldNotConfirmIdentity,
    ) {
        viewModelScope.launch {
            if (!biometricGate.authenticate(authReason)) {
                _state.update { it.copy(error = authFailure) }
                return@launch
            }
            runCatching {
                identityStore.backUpRecoveryPhraseToDeviceSecureStorage()
            }.onSuccess {
                _state.update {
                    it.copy(
                        statusMessage = YouStatusCopy.IdentityBackupSaved,
                        error = null,
                    )
                }
            }.onFailure {
                _state.update { it.copy(error = YouStatusCopy.CouldNotBackUpAnkyIdentity) }
            }
        }
    }

    /**
     * Staged import: [WriterIdentityStore.importRecoveryPhrase] validates the
     * BIP-39 checksum before anything is replaced, so a mistyped word throws
     * and the current access is untouched. The thrown message is mapped to
     * the current iOS copy in [recoveryImportErrorMessage].
     */
    fun importRecoveryPhrase(
        text: String,
        authReason: String = YouStatusCopy.RecoverAnkyAccessReason,
        authFailure: String = YouStatusCopy.CouldNotConfirmIdentity,
        onImported: () -> Unit = {},
    ) {
        viewModelScope.launch {
            if (!biometricGate.authenticate(authReason)) {
                _state.update { it.copy(error = authFailure) }
                return@launch
            }
            runCatching {
                identityStore.importRecoveryPhrase(text)
            }.onSuccess { identity ->
                accountIdState.value = identity.accountId
                creditState.value = CreditState(false, null, "no credit packs available")
                _state.update {
                    it.copy(
                        accountId = identity.accountId,
                        recoveryPhrase = null,
                        statusMessage = YouStatusCopy.RecoveryPhraseImported,
                        error = null,
                    )
                }
                onImported()
            }.onFailure { error ->
                _state.update { it.copy(error = recoveryImportErrorMessage(error)) }
            }
        }
    }

    fun setAppLock(enabled: Boolean) {
        viewModelScope.launch {
            settingsStore.setAppLockEnabled(enabled)
        }
    }

    fun setDailyReminder(enabled: Boolean) {
        viewModelScope.launch {
            runCatching {
                settingsStore.setDailyReminderEnabled(enabled)
                reminderScheduler.setEnabled(enabled, _state.value.dailyReminderMinutes)
            }.onSuccess {
                if (enabled) {
                    _state.update { it.copy(error = null) }
                }
            }.onFailure {
                _state.update { it.copy(error = YouStatusCopy.CouldNotScheduleDailyReminder) }
            }
        }
    }

    fun dailyReminderPermissionDenied() {
        viewModelScope.launch {
            settingsStore.setDailyReminderEnabled(false)
            reminderScheduler.setEnabled(false, _state.value.dailyReminderMinutes)
            _state.update { it.copy(error = "Notifications are not allowed for ANKY.") }
        }
    }

    fun setDailyReminderTime(minutes: Int) {
        viewModelScope.launch {
            val clamped = minutes.coerceIn(0, 23 * 60 + 59)
            runCatching {
                settingsStore.setDailyReminderMinutes(clamped)
                reminderScheduler.setReminderMinutes(clamped)
            }.onSuccess {
                _state.update {
                    it.copy(
                        dailyReminderMinutes = clamped,
                        error = null,
                    )
                }
            }.onFailure {
                _state.update {
                    it.copy(error = YouStatusCopy.CouldNotScheduleDailyReminder)
                }
            }
        }
    }

    fun setMirrorBaseUrl(url: String) {
        viewModelScope.launch { settingsStore.setMirrorBaseUrl(url.trim()) }
    }

    /**
     * Deprecated credits-economy remnant, no longer reachable from the UI.
     * Kept compiling until the cleanup phase deletes the credits client;
     * the only live effect is refreshing the inert cached balance.
     */
    fun refreshCredits() {
        viewModelScope.launch {
            val accountId = if (_state.value.accountId.isBlank()) {
                configureCreditsForCurrentIdentity() ?: return@launch
            } else {
                _state.value.accountId.also { creditsClient.configure(it) }
            }
            val refreshed = creditsClient.refresh()
            reflectionCreditCache.storeBalance(refreshed.balance, accountId)
            creditState.value = refreshed
        }
    }

    /** Restore is subscription truth now: RevenueCat restore via [EntitlementStore]. */
    fun restorePurchases() {
        viewModelScope.launch {
            if (_state.value.isRestoringPurchases) return@launch
            val store = entitlementStore
            if (store == null) {
                _state.update { it.copy(error = YouStatusCopy.SubscriptionTruthUnavailable) }
                return@launch
            }
            _state.update { it.copy(isRestoringPurchases = true, statusMessage = null, error = null) }
            try {
                store.restore()
                val line = store.state.value.restoreStatusLine
                if (line != null) {
                    _state.update { it.copy(statusMessage = line) }
                }
            } finally {
                _state.update { it.copy(isRestoringPurchases = false) }
            }
        }
    }

    fun exportArchive() {
        viewModelScope.launch {
            runCatching {
                exporter.exportArchiveZip()
            }.onSuccess { exportedFile ->
                _state.update {
                    it.copy(
                        exportedFile = exportedFile,
                        error = null,
                    )
                }
            }.onFailure {
                _state.update {
                    it.copy(
                        exportedFile = null,
                        error = YouStatusCopy.CouldNotCreateBackupZip,
                    )
                }
            }
        }
    }

    fun enableEncryptedBackup(
        authReason: String = YouStatusCopy.EnableEncryptedBackupReason,
        authFailure: String = YouStatusCopy.CouldNotConfirmIdentity,
    ) {
        viewModelScope.launch {
            if (!biometricGate.authenticate(authReason)) {
                _state.update { it.copy(error = authFailure) }
                return@launch
            }
            _state.update { it.copy(isEncryptedBackupWorking = true, error = null, statusMessage = null) }
            runCatching {
                encryptedBackupStore.enableAndBackUpNow()
            }.onSuccess {
                refresh()
                _state.update {
                    it.copy(
                        isEncryptedBackupWorking = false,
                        statusMessage = YouStatusCopy.EncryptedBackupOn,
                        error = null,
                    )
                }
            }.onFailure { error ->
                if ((error as? AndroidEncryptedBackupException)?.reason == AndroidEncryptedBackupError.NoLocalData) {
                    encryptedBackupStore.setEnabled(true)
                    refresh()
                    _state.update {
                        it.copy(
                            isEncryptedBackupWorking = false,
                            statusMessage = YouStatusCopy.EncryptedBackupOnAfterNextWriting,
                            error = null,
                        )
                    }
                } else {
                    _state.update {
                        it.copy(
                            isEncryptedBackupWorking = false,
                            error = encryptedBackupErrorMessage(error, YouStatusCopy.CouldNotEnableEncryptedBackup),
                        )
                    }
                }
            }
        }
    }

    fun disableEncryptedBackup() {
        encryptedBackupStore.setEnabled(false)
        refresh()
        _state.update { it.copy(statusMessage = YouStatusCopy.EncryptedBackupOff, error = null) }
    }

    fun backUpEncryptedNow() {
        viewModelScope.launch {
            _state.update { it.copy(isEncryptedBackupWorking = true, error = null, statusMessage = null) }
            runCatching {
                encryptedBackupStore.backUpNow()
            }.onSuccess {
                refresh()
                _state.update {
                    it.copy(
                        isEncryptedBackupWorking = false,
                        statusMessage = YouStatusCopy.EncryptedBackupUpdated,
                        error = null,
                    )
                }
            }.onFailure { error ->
                _state.update {
                    it.copy(
                        isEncryptedBackupWorking = false,
                        error = encryptedBackupErrorMessage(error, YouStatusCopy.CouldNotUpdateEncryptedBackup),
                    )
                }
            }
        }
    }

    fun restoreEncryptedBackup(
        authReason: String = YouStatusCopy.RestoreEncryptedBackupReason,
        authFailure: String = YouStatusCopy.CouldNotConfirmIdentity,
    ) {
        viewModelScope.launch {
            if (!biometricGate.authenticate(authReason)) {
                _state.update { it.copy(error = authFailure) }
                return@launch
            }
            _state.update { it.copy(isEncryptedBackupWorking = true, error = null, statusMessage = null) }
            runCatching {
                encryptedBackupStore.restore()
            }.onSuccess { result ->
                val sessions = indexStore.load()
                _state.update {
                    it.copy(
                        isEncryptedBackupWorking = false,
                        isEncryptedBackupEnabled = true,
                        encryptedBackupLastDate = encryptedBackupStore.status().lastBackupDate,
                        localAnkyFileCount = sessions.size,
                        completeAnkyCount = sessions.count { session -> session.isComplete },
                        totalWritingMinutes = totalWritingMinutes(sessions),
                        currentStreak = currentStreak(sessions.filter { session -> session.isComplete }.map { session -> session.createdAt }),
                        reflectionCount = localReflectionCount(),
                        completeAnkySessions = completeSessions(sessions),
                        statusMessage = "Imported ${pluralize(result.ankyCount, ".anky file", ".anky files")} and ${pluralize(result.reflectionCount, "reflection", "reflections")}.",
                        error = null,
                    )
                }
            }.onFailure { error ->
                _state.update {
                    it.copy(
                        isEncryptedBackupWorking = false,
                        error = encryptedBackupErrorMessage(error, "Anky could not restore from encrypted backup."),
                    )
                }
            }
        }
    }

    fun prepareFormattedWritingExport() {
        viewModelScope.launch {
            runCatching {
                exporter.exportFormattedWritings()
            }.onSuccess { exportFile ->
                _state.update {
                    it.copy(
                        formattedWritingExportFile = exportFile,
                        statusMessage = if (exportFile == null) YouStatusCopy.NoWritingToExportYet else it.statusMessage,
                        error = null,
                    )
                }
            }.onFailure {
                _state.update {
                    it.copy(
                        formattedWritingExportFile = null,
                        error = YouStatusCopy.CouldNotCreateWritingExport,
                    )
                }
            }
        }
    }

    fun importBackup(uri: Uri) {
        viewModelScope.launch {
            runCatching {
                backupImporter.importBackup(uri)
            }.onSuccess { result ->
                val sessions = indexStore.load()
                _state.update {
                    it.copy(
                        localAnkyFileCount = sessions.size,
                        completeAnkyCount = sessions.count { session -> session.isComplete },
                        totalWritingMinutes = totalWritingMinutes(sessions),
                        currentStreak = currentStreak(sessions.filter { session -> session.isComplete }.map { session -> session.createdAt }),
                        reflectionCount = localReflectionCount(),
                        completeAnkySessions = completeSessions(sessions),
                        statusMessage = "Imported ${pluralize(result.ankyCount, ".anky file", ".anky files")} and ${pluralize(result.reflectionCount, "reflection", "reflections")}.",
                        error = null,
                    )
                }
            }.onFailure { error ->
                _state.update { it.copy(error = error.message ?: "Could not import that backup.") }
            }
        }
    }

    fun refresh() {
        val accountId = _state.value.accountId.ifBlank {
            runCatching { identityStore.loadOrCreate().accountId }
                .onSuccess { accountIdState.value = it }
                .getOrDefault("")
        }
        val cachedCredits = if (accountId.isBlank()) null else cachedCreditState(reflectionCreditCache.balance(accountId))
        val sessions = indexStore.rebuild(archive, reflectionStore)
        val encryptedBackupStatus = encryptedBackupStore.status()
        _state.update {
            it.copy(
                accountId = accountId.ifBlank { it.accountId },
                creditState = cachedCredits ?: it.creditState,
                hasClaimedFreeCredits = if (accountId.isBlank()) it.hasClaimedFreeCredits else reflectionCreditCache.hasClaimedFreeCredits(accountId),
                isEncryptedBackupEnabled = encryptedBackupStatus.isEnabled,
                encryptedBackupLastDate = encryptedBackupStatus.lastBackupDate,
                completeAnkyCount = sessions.count { session -> session.isComplete },
                localAnkyFileCount = sessions.size,
                totalWritingMinutes = totalWritingMinutes(sessions),
                currentStreak = currentStreak(sessions.filter { session -> session.isComplete }.map { session -> session.createdAt }),
                reflectionCount = localReflectionCount(),
                completeAnkySessions = completeSessions(sessions),
            )
        }
        if (cachedCredits != null) creditState.value = cachedCredits
    }

    fun refreshLocalStats() {
        refresh()
    }

    fun clearLocalWritingData() {
        viewModelScope.launch {
            runCatching {
                archive.clear()
                reflectionStore.clear()
                indexStore.clear()
            }.onSuccess {
                _state.update {
                    it.copy(
                        localAnkyFileCount = 0,
                        completeAnkyCount = 0,
                        totalWritingMinutes = 0,
                        currentStreak = 0,
                        reflectionCount = 0,
                        completeAnkySessions = emptyList(),
                        exportedFile = null,
                        statusMessage = YouStatusCopy.LocalWritingDataCleared,
                        error = null,
                    )
                }
            }.onFailure {
                _state.update { state -> state.copy(error = "Could not clear local writing data.") }
            }
        }
    }

    fun rebuildSessionIndex() {
        viewModelScope.launch {
            runCatching {
                indexStore.rebuild(archive, reflectionStore)
            }.onSuccess { sessions ->
                _state.update {
                    it.copy(
                        localAnkyFileCount = sessions.size,
                        completeAnkyCount = sessions.count { session -> session.isComplete },
                        totalWritingMinutes = totalWritingMinutes(sessions),
                        currentStreak = currentStreak(sessions.filter { session -> session.isComplete }.map { session -> session.createdAt }),
                        reflectionCount = localReflectionCount(),
                        completeAnkySessions = completeSessions(sessions),
                        statusMessage = YouStatusCopy.MapIndexRepaired,
                        error = null,
                    )
                }
            }.onFailure {
                _state.update { it.copy(error = "Could not rebuild the local session index.") }
            }
        }
    }

    fun clearLocalReflections() {
        viewModelScope.launch {
            runCatching {
                reflectionStore.clear()
                indexStore.rebuild(archive, reflectionStore)
            }.onSuccess { sessions ->
                _state.update {
                    it.copy(
                        localAnkyFileCount = sessions.size,
                        completeAnkyCount = sessions.count { session -> session.isComplete },
                        totalWritingMinutes = totalWritingMinutes(sessions),
                        currentStreak = currentStreak(sessions.filter { session -> session.isComplete }.map { session -> session.createdAt }),
                        reflectionCount = 0,
                        completeAnkySessions = completeSessions(sessions),
                        statusMessage = YouStatusCopy.LocalReflectionsCleared,
                        error = null,
                    )
                }
            }.onFailure {
                _state.update { it.copy(error = "Could not clear local reflections.") }
            }
        }
    }

    fun clearLocalArchive() {
        viewModelScope.launch {
            runCatching {
                archive.clear()
                indexStore.clear()
            }.onSuccess {
                _state.update {
                    it.copy(
                        localAnkyFileCount = 0,
                        completeAnkyCount = 0,
                        totalWritingMinutes = 0,
                        currentStreak = 0,
                        reflectionCount = localReflectionCount(),
                        completeAnkySessions = emptyList(),
                        exportedFile = null,
                        statusMessage = YouStatusCopy.LocalAnkyArchiveCleared,
                        error = null,
                    )
                }
            }.onFailure {
                _state.update { it.copy(error = "Could not clear local .anky files.") }
            }
        }
    }

    fun deleteAccountAndDataEverywhere(onDeleted: () -> Unit = {}) {
        viewModelScope.launch {
            runCatching {
                archive.clear()
                reflectionStore.clear()
                requestStore.clear()
                indexStore.clear()
                activeDraftStore.clear()
                reminderScheduler.setEnabled(false, 9 * 60)
                settingsStore.resetToDefaults()
                appOpenStore.clear()
                encryptedBackupStore.deleteBackupAndDisable()
                identityStore.resetForDevelopment()
                creditsClient.logOutIfConfigured()
                reflectionCreditCache.clear()
            }.onSuccess {
                creditState.value = CreditState(false, null, "no credit packs available")
                accountIdState.value = ""
                _state.update {
                    it.copy(
                        accountId = "",
                        recoveryPhrase = null,
                        appLockEnabled = false,
                        dailyReminderEnabled = false,
                        dailyReminderMinutes = 9 * 60,
                        mirrorBaseUrl = BuildConfig.DEFAULT_MIRROR_BASE_URL,
                        creditState = CreditState(false, null, "no credit packs available"),
                        hasClaimedFreeCredits = false,
                        purchasingCreditPackageId = null,
                        isRestoringPurchases = false,
                        exportedFile = null,
                        formattedWritingExportFile = null,
                        isEncryptedBackupEnabled = false,
                        encryptedBackupLastDate = null,
                        isEncryptedBackupWorking = false,
                        localAnkyFileCount = 0,
                        completeAnkyCount = 0,
                        totalWritingMinutes = 0,
                        currentStreak = 0,
                        reflectionCount = 0,
                        completeAnkySessions = emptyList(),
                        statusMessage = YouStatusCopy.AccountAndDataDeleted,
                        error = null,
                    )
                }
                onDeleted()
            }.onFailure {
                _state.update { it.copy(error = YouStatusCopy.CouldNotDeleteAllAccountData) }
            }
        }
    }

    fun resetIdentityForDevelopment() {
        viewModelScope.launch {
            runCatching {
                identityStore.resetForDevelopment()
                identityStore.loadOrCreate()
            }.onSuccess { identity ->
                accountIdState.value = identity.accountId
                creditState.value = CreditState(false, null, "no credit packs available")
                _state.update {
                    it.copy(
                        accountId = identity.accountId,
                        recoveryPhrase = null,
                        statusMessage = YouStatusCopy.LocalIdentityReset,
                        error = null,
                    )
                }
            }.onFailure {
                _state.update { it.copy(error = "Could not reset the local identity.") }
            }
        }
    }

    fun dismissMessages() {
        _state.update { it.copy(statusMessage = null, error = null) }
    }

    private fun currentStreak(instants: List<java.time.Instant>): Int {
        val zone = java.time.ZoneOffset.UTC
        val days = instants.map { it.atZone(zone).toLocalDate() }.toSet()
        if (days.isEmpty()) return 0
        var cursor = java.time.LocalDate.now(zone)
        if (!days.contains(cursor)) return 0
        var streak = 0
        while (days.contains(cursor)) {
            streak += 1
            cursor = cursor.minusDays(1)
        }
        return streak
    }

    private suspend fun configureCreditsForCurrentIdentity(): String? {
        val accountId = _state.value.accountId.ifBlank {
            val identity = runCatching { identityStore.loadOrCreate() }.getOrElse {
                return null
            }
            accountIdState.value = identity.accountId
            identity.accountId
        }
        creditsClient.configure(accountId)
        return accountId
    }

    private fun totalWritingMinutes(sessions: List<SessionSummary>): Int {
        if (sessions.isEmpty()) return 0
        val totalDurationMs = sessions.sumOf { it.durationMs }
        return maxOf(1, ((totalDurationMs + 59_999) / 60_000).toInt())
    }

    private fun localReflectionCount(): Int = reflectionStore.fileList().size

    private fun completeSessions(sessions: List<SessionSummary>): List<SessionSummary> =
        sessions.filter { it.isComplete }.sortedByDescending { it.createdAt }

    private fun pluralize(count: Int, singular: String, plural: String): String =
        "$count ${if (count == 1) singular else plural}"

    companion object {
        fun formatReminderTime(minutes: Int): String {
            val hour = (minutes / 60).coerceIn(0, 23)
            val minute = (minutes % 60).coerceIn(0, 59)
            return "${hour.toString().padStart(2, '0')}:${minute.toString().padStart(2, '0')}"
        }
    }
}

/**
 * Maps [WriterIdentityStore.importRecoveryPhrase] failures to the current iOS
 * copy. The store validates the BIP-39 checksum on import (never on load), so
 * a mistyped word surfaces here with nothing replaced.
 */
internal fun recoveryImportErrorMessage(error: Throwable): String =
    when (error.message) {
        "Recovery phrase must contain 12 words." -> "Recovery words must be 12 words."
        "Recovery phrase contains an unsupported word." -> "Recovery words contain an unrecognized word."
        "Recovery phrase checksum is invalid." -> YouStatusCopy.RecoveryWordsInvalidChecksum
        else -> "Could not recover that identity."
    }

internal fun encryptedBackupErrorMessage(error: Throwable, fallback: String): String =
    (error as? AndroidEncryptedBackupException)?.reason?.copy ?: error.message ?: fallback

internal fun mergeRefreshedYouState(previous: YouState, refreshed: YouState): YouState =
    refreshed.copy(
        recoveryPhrase = previous.recoveryPhrase,
        subscription = previous.subscription,
        isSubscriptionTruthAvailable = previous.isSubscriptionTruthAvailable,
        purchasingCreditPackageId = previous.purchasingCreditPackageId,
        isRestoringPurchases = previous.isRestoringPurchases,
        isEncryptedBackupWorking = previous.isEncryptedBackupWorking,
        exportedFile = previous.exportedFile,
        formattedWritingExportFile = previous.formattedWritingExportFile,
        statusMessage = previous.statusMessage,
        error = previous.error,
    )

internal fun localIdentityLoadFailureState(previous: YouState): YouState =
    previous.copy(
        creditState = CreditState(false, null, "no credit packs available"),
        error = YouStatusCopy.CouldNotLoadLocalWriterIdentity,
    )

/** Deprecated credits-economy remnant (cleanup phase deletes). */
internal fun creditLoadFailureState(): CreditState =
    CreditState(false, null, YouStatusCopy.CouldNotLoadCredits)

/** Deprecated credits-economy remnant (cleanup phase deletes). */
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

// region Subscription presentation (port of iOS AnkySettingsView subscription section)

/** Google Play's manage-subscriptions surface — the Android "App Store subscriptions". */
internal const val PlayManageSubscriptionsUrl = "https://play.google.com/store/account/subscriptions"

/** A human answers — same channel as iOS. */
internal const val FounderChatUrl = "https://t.me/ankytheapp"

internal fun subscriptionStatusTitle(subscription: EntitlementState): String {
    if (subscription.isEntitled) {
        if (subscription.isPromotionalEntitlement) {
            return "Complimentary access"
        }
        if (subscription.isInIntroTrial) {
            return "Free trial"
        }
        return when (subscription.activeProductId) {
            AnkyPurchasesConfig.YEARLY_PRODUCT_ID -> "Yearly subscription"
            AnkyPurchasesConfig.MONTHLY_PRODUCT_ID -> "Monthly subscription"
            else -> "Active subscription"
        }
    }
    return "Free"
}

internal fun subscriptionStatusDetail(
    subscription: EntitlementState,
    isSubscriptionTruthAvailable: Boolean,
    formatDate: (Long) -> String = ::formatSubscriptionDate,
): String {
    if (subscription.isEntitled) {
        if (subscription.isPromotionalEntitlement) {
            val endMillis = subscription.activeExpirationDateMillis
                ?: return "Granted access, open-ended. Nothing is charged and nothing renews."
            return "Granted access through ${formatDate(endMillis)}. Nothing is charged — when it ends, the practice simply asks again."
        }
        val renewalMillis = subscription.activeExpirationDateMillis
        if (renewalMillis != null) {
            val price = activeSubscriptionPriceLine(subscription)
            val date = formatDate(renewalMillis)
            if (subscription.isInIntroTrial) {
                return "Trial ends $date. You will be charged $price that day unless you cancel in Google Play subscriptions."
            }
            return "Renews $date. You will be charged $price unless you cancel in Google Play subscriptions."
        }
        return "Anky is unlocked on this Google account. ${activeSubscriptionPriceLine(subscription)} on the active plan. Manage renewal from your Google Play subscriptions."
    }
    if (!isSubscriptionTruthAvailable || subscription.packages.isEmpty()) {
        return "Plans are loading. You can still write for free."
    }
    return "Writing is free. The full practice starts at ${yearlySubscriptionPriceLine(subscription)}."
}

internal fun activeSubscriptionPriceLine(
    subscription: EntitlementState,
    locale: Locale = Locale.getDefault(),
): String {
    val pkg = subscription.activePackage ?: subscription.yearlyPackage
    if (subscription.activeProductId == AnkyPurchasesConfig.MONTHLY_PRODUCT_ID) {
        return "${SubscriptionPriceFormatter.price(pkg, fallback = "$11.99", locale = locale)}/month"
    }
    return "${SubscriptionPriceFormatter.price(pkg, fallback = "$88", locale = locale)}/year"
}

internal fun yearlySubscriptionPriceLine(
    subscription: EntitlementState,
    locale: Locale = Locale.getDefault(),
): String =
    "${SubscriptionPriceFormatter.price(subscription.yearlyPackage, fallback = "$88", locale = locale)}/year"

private fun formatSubscriptionDate(millis: Long): String =
    DateTimeFormatter
        .ofLocalizedDate(FormatStyle.MEDIUM)
        .withLocale(Locale.getDefault())
        .withZone(ZoneId.systemDefault())
        .format(Instant.ofEpochMilli(millis))

// endregion

internal fun identityStatus(state: YouState): String = "Local identity"

internal object YouStatusCopy {
    const val ShowRecoveryWordsReason = "Show your Anky recovery words."
    const val BackUpRecoveryWordsReason = "Back up your Anky recovery words to device secure storage."
    const val RecoverAnkyAccessReason = "Recover your Anky access."
    const val EnableEncryptedBackupReason = "Enable encrypted Anky backup."
    const val RestoreEncryptedBackupReason = "Restore your encrypted Anky backup."
    const val CouldNotConfirmIdentity = "Could not confirm identity."
    const val IdentityBackupSaved = "Recovery words saved to device secure storage. Use Data export for writing and reflection backups."
    const val RecoveryPhraseImported = "Identity recovered."
    const val RecoveryWordsInvalidChecksum = "These words don't form a valid recovery phrase — one of them is probably mistyped. Check each word and try again. Nothing was changed."
    const val MapIndexRepaired = "Map index repaired."
    const val LocalReflectionsCleared = "Local reflections cleared."
    const val LocalAnkyArchiveCleared = "Local .anky archive cleared."
    const val LocalWritingDataCleared = "Local writing data cleared."
    const val LocalIdentityReset = "Local identity reset."
    const val AccountAndDataDeleted = "Account and data deleted from this device."
    const val CouldNotDeleteAllAccountData = "Could not delete all account data."
    const val CouldNotCreateBackupZip = "Could not create a backup zip."
    const val CouldNotCreateWritingExport = "Could not create a writing export."
    const val NoWritingToExportYet = "There is no writing to export yet."
    const val CouldNotLoadLocalWriterIdentity = "Could not load the local Base identity."
    const val CouldNotLoadRecoveryPhrase = "Could not load the recovery words."
    const val CouldNotBackUpAnkyIdentity = "Could not back up Anky identity."
    const val CouldNotScheduleDailyReminder = "Could not schedule the daily reminder."
    const val CouldNotLoadCredits = "Could not load credits."
    const val SubscriptionTruthUnavailable = "Subscriptions are not wired up on this build yet."
    const val EncryptedBackupOn = "Encrypted backup is on."
    const val EncryptedBackupOff = "Encrypted backup is off."
    const val EncryptedBackupUpdated = "Encrypted backup updated."
    const val EncryptedBackupOnAfterNextWriting = "Encrypted backup is on. It will run after your next writing session."
    const val CouldNotEnableEncryptedBackup = "Could not enable encrypted backup."
    const val CouldNotUpdateEncryptedBackup = "Could not update encrypted backup."
}
