package inc.anky.android.feature.you

import android.app.Activity
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import android.net.Uri
import inc.anky.android.BuildConfig
import inc.anky.android.app.UserSettingsStore
import inc.anky.android.core.credits.CreditCatalog
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
import inc.anky.android.core.storage.AppOpenStore
import inc.anky.android.core.storage.BackupImporter
import inc.anky.android.core.storage.BackupExporting
import inc.anky.android.core.storage.LocalAnkyArchive
import inc.anky.android.core.storage.ReflectionRequestStore
import inc.anky.android.core.storage.ReflectionStore
import inc.anky.android.core.storage.SessionIndexStore
import inc.anky.android.core.storage.SessionSummary
import java.io.File
import java.net.URLEncoder
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
    val creditState: CreditState = CreditState(false, null, "no credit packs available"),
    val hasClaimedFreeCredits: Boolean = false,
    val purchasingCreditPackageId: String? = null,
    val isRestoringPurchases: Boolean = false,
    val exportedFile: File? = null,
    val formattedWritingExportFile: File? = null,
    val localAnkyFileCount: Int = 0,
    val completeAnkyCount: Int = 0,
    val totalWritingMinutes: Int = 0,
    val currentStreak: Int = 0,
    val reflectionCount: Int = 0,
    val completeAnkySessions: List<SessionSummary> = emptyList(),
    val statusMessage: String? = null,
    val error: String? = null,
) {
    val freeCreditMessage: String
        get() = PrivacyMessages.freeCreditMessage(accountId, "${BuildConfig.VERSION_NAME} ${BuildConfig.VERSION_CODE}")

    val freeCreditWhatsAppUrl: String
        get() = Uri.parse("https://wa.me/56985491126")
            .buildUpon()
            .appendQueryParameter("text", freeCreditMessage)
            .build()
            .toString()

    val supportFeedbackEmailUrl: String
        get() {
            val subject = mailtoQueryValue("Anky support / feedback")
            val body = mailtoQueryValue("account id: $accountId\n\n")
            return "mailto:support@anky.app?subject=$subject&body=$body"
        }

    val presentedCreditBalance: Int?
        get() = if (hasClaimedFreeCredits) creditState.balance else ReflectionCreditPresentation.FirstGiftCount

    val hasUnspentGiftCredit: Boolean
        get() = !hasClaimedFreeCredits

    val canPurchaseCredits: Boolean
        get() = hasClaimedFreeCredits

    val creditDetailTitle: String
        get() = if (hasUnspentGiftCredit) {
            ReflectionCreditPresentation.FirstGiftCount.toString()
        } else {
            creditState.balance?.toString() ?: "..."
        }

    val creditDetailCaption: String
        get() = if (hasUnspentGiftCredit) YouStatusCopy.CreditGiftCaption else "credits"
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
    private val biometricGate: BiometricGate,
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
                YouState(
                    accountId = accountId,
                    appLockEnabled = settings.appLockEnabled,
                    dailyReminderEnabled = settings.dailyReminderEnabled,
                    dailyReminderMinutes = settings.dailyReminderMinutes,
                    mirrorBaseUrl = settings.mirrorBaseUrl,
                    creditState = credits,
                    hasClaimedFreeCredits = reflectionCreditCache.hasClaimedFreeCredits(accountId),
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
    }

    fun revealRecoveryPhrase() {
        viewModelScope.launch {
            if (!biometricGate.authenticate("Show your ANKY recovery phrase.")) {
                _state.update { it.copy(error = "Could not confirm identity.") }
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

    fun backUpIdentityToDeviceSecureStorage() {
        viewModelScope.launch {
            if (!biometricGate.authenticate("Back up your ANKY recovery phrase to device secure storage.")) {
                _state.update { it.copy(error = "Could not confirm identity.") }
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

    fun importRecoveryPhrase(text: String, onImported: () -> Unit = {}) {
        viewModelScope.launch {
            if (!biometricGate.authenticate("Recover your ANKY local identity.")) {
                _state.update { it.copy(error = "Could not confirm identity.") }
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

    fun refreshCredits() {
        viewModelScope.launch {
            creditState.value = creditState.value.copy(message = "loading credit packs", isLoading = true)
            val accountId = if (_state.value.accountId.isBlank()) {
                configureCreditsForCurrentIdentity() ?: return@launch
            } else {
                _state.value.accountId.also { creditsClient.configure(it) }
            }
            val refreshed = creditsClient.refresh()
            reflectionCreditCache.storeBalance(refreshed.balance, accountId)
            creditState.value = refreshed
            if (refreshed.message == YouStatusCopy.CouldNotLoadCredits) {
                _state.update { it.copy(error = YouStatusCopy.CouldNotLoadCredits) }
            } else {
                _state.update { it.copy(error = null) }
            }
        }
    }

    fun purchaseCredits(packageId: String, activity: Activity?) {
        viewModelScope.launch {
            if (!_state.value.canPurchaseCredits) {
                _state.update { it.copy(statusMessage = YouStatusCopy.SpendGiftBeforeBuying, error = null) }
                return@launch
            }
            if (_state.value.purchasingCreditPackageId != null) return@launch
            _state.update { it.copy(purchasingCreditPackageId = packageId) }
            try {
                creditState.value = creditState.value.copy(message = "loading credit packs", isLoading = true)
                val accountId = configureCreditsForCurrentIdentity() ?: return@launch
                val refreshed = creditsClient.purchase(packageId, activity)
                reflectionCreditCache.storeBalance(refreshed.balance, accountId)
                creditState.value = refreshed
                when (refreshed.message) {
                    "Could not complete that credit purchase." -> _state.update { it.copy(error = "Could not complete that credit purchase.") }
                    "Credits updated." -> _state.update { it.copy(statusMessage = "Credits updated.", error = null) }
                }
            } finally {
                _state.update { it.copy(purchasingCreditPackageId = null) }
            }
        }
    }

    fun restorePurchases() {
        viewModelScope.launch {
            if (_state.value.isRestoringPurchases) return@launch
            _state.update { it.copy(isRestoringPurchases = true, statusMessage = null, error = null) }
            try {
                creditState.value = creditState.value.copy(message = "restoring purchases", isLoading = true)
                val accountId = configureCreditsForCurrentIdentity() ?: return@launch
                val restored = creditsClient.restorePurchases()
                reflectionCreditCache.storeBalance(restored.balance, accountId)
                creditState.value = restored
                when (restored.message) {
                    CreditCatalog.RestoreSuccessMessage -> _state.update {
                        it.copy(statusMessage = CreditCatalog.RestoreSuccessMessage, error = null)
                    }
                    CreditCatalog.RestoreFailureMessage -> _state.update {
                        it.copy(error = CreditCatalog.RestoreFailureMessage)
                    }
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
        _state.update {
            it.copy(
                accountId = accountId.ifBlank { it.accountId },
                creditState = cachedCredits ?: it.creditState,
                hasClaimedFreeCredits = if (accountId.isBlank()) it.hasClaimedFreeCredits else reflectionCreditCache.hasClaimedFreeCredits(accountId),
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
                creditState.value = creditLoadFailureState()
                _state.update { state -> state.copy(error = YouStatusCopy.CouldNotLoadCredits) }
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

internal fun recoveryImportErrorMessage(error: Throwable): String =
    when (error.message) {
        "Recovery phrase must contain 12 words." -> "Recovery phrase must be 12 words."
        "Recovery phrase contains an unsupported word." -> "Recovery phrase contains an unrecognized word."
        else -> "Could not recover that identity."
    }

internal fun mergeRefreshedYouState(previous: YouState, refreshed: YouState): YouState =
    refreshed.copy(
        recoveryPhrase = previous.recoveryPhrase,
        purchasingCreditPackageId = previous.purchasingCreditPackageId,
        isRestoringPurchases = previous.isRestoringPurchases,
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

internal fun creditLoadFailureState(): CreditState =
    CreditState(false, null, YouStatusCopy.CouldNotLoadCredits)

internal object YouStatusCopy {
    const val IdentityBackupSaved = "Recovery phrase saved to device secure storage. Use Data export for writing and reflection backups."
    const val RecoveryPhraseImported = "Identity recovered."
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
    const val CreditGiftSummary = "2 reflections - This device"
    const val CreditGiftCaption = "device gift"
    const val CreditGiftPrompt = "This device has two free reflections from Anky. Use them before buying more credits."
    const val CreditPacksLocked = "Credit packs unlock after this device spends its first two reflections"
    const val CreditGiftDetail = "Your first two reflections are tied to this device. After they are used, this screen will let you buy more credits."
    const val SpendGiftBeforeBuying = "Use this device's first two reflections before buying more credits."
    const val CouldNotLoadLocalWriterIdentity = "Could not load the local Base identity."
    const val CouldNotLoadRecoveryPhrase = "Could not load the recovery phrase."
    const val CouldNotBackUpAnkyIdentity = "Could not back up Anky identity."
    const val CouldNotScheduleDailyReminder = "Could not schedule the daily reminder."
    const val CouldNotLoadCredits = "Could not load credits."
}
