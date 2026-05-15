package inc.anky.android.feature.you

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import inc.anky.android.BuildConfig
import inc.anky.android.app.UserSettingsStore
import inc.anky.android.core.credits.CreditState
import inc.anky.android.core.credits.CreditsClient
import inc.anky.android.core.identity.BiometricGate
import inc.anky.android.core.identity.WriterIdentityStore
import inc.anky.android.core.notifications.DailyReminderScheduler
import inc.anky.android.core.privacy.PrivacyMessages
import inc.anky.android.core.storage.Exporter
import java.io.File
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class YouState(
    val publicKey: String = "",
    val recoveryPhrase: String? = null,
    val appLockEnabled: Boolean = false,
    val dailyReminderEnabled: Boolean = false,
    val mirrorBaseUrl: String = BuildConfig.DEFAULT_MIRROR_BASE_URL,
    val creditState: CreditState = CreditState(false, null, "RevenueCat Android products are not configured in this build."),
    val exportedFile: File? = null,
    val error: String? = null,
) {
    val freeCreditMessage: String
        get() = PrivacyMessages.freeCreditMessage(publicKey, BuildConfig.VERSION_NAME)
}

class YouViewModel(
    private val identityStore: WriterIdentityStore,
    private val settingsStore: UserSettingsStore,
    private val reminderScheduler: DailyReminderScheduler,
    private val creditsClient: CreditsClient,
    private val exporter: Exporter,
    private val biometricGate: BiometricGate,
) : ViewModel() {
    private val _state = MutableStateFlow(YouState())
    val state: StateFlow<YouState> = _state

    init {
        viewModelScope.launch {
            val identity = identityStore.loadOrCreate()
            creditsClient.configure(identity.publicKey)
            combine(settingsStore.settings, MutableStateFlow(creditsClient.refresh())) { settings, credits ->
                YouState(
                    publicKey = identity.publicKey,
                    appLockEnabled = settings.appLockEnabled,
                    dailyReminderEnabled = settings.dailyReminderEnabled,
                    mirrorBaseUrl = settings.mirrorBaseUrl,
                    creditState = credits,
                )
            }.collect { _state.value = it }
        }
    }

    fun revealRecoveryPhrase() {
        viewModelScope.launch {
            if (!biometricGate.authenticate("Reveal recovery phrase")) {
                _state.update { it.copy(error = "Local authentication is required.") }
                return@launch
            }
            _state.update {
                it.copy(
                    recoveryPhrase = identityStore.loadOrCreateRecoveryPhrase().text,
                    error = null,
                )
            }
        }
    }

    fun copyRecoveryPhrase(copy: (String) -> Unit) {
        viewModelScope.launch {
            if (!biometricGate.authenticate("Copy recovery phrase")) {
                _state.update { it.copy(error = "Local authentication is required.") }
                return@launch
            }
            val phrase = identityStore.loadOrCreateRecoveryPhrase().text
            copy(phrase)
            _state.update { it.copy(error = null) }
        }
    }

    fun setAppLock(enabled: Boolean) {
        viewModelScope.launch {
            if (enabled && !biometricGate.authenticate("Enable app lock")) {
                _state.update { it.copy(error = "Local authentication is required.") }
                return@launch
            }
            settingsStore.setAppLockEnabled(enabled)
        }
    }

    fun setDailyReminder(enabled: Boolean) {
        viewModelScope.launch {
            settingsStore.setDailyReminderEnabled(enabled)
            reminderScheduler.setEnabled(enabled)
        }
    }

    fun setMirrorBaseUrl(url: String) {
        viewModelScope.launch { settingsStore.setMirrorBaseUrl(url.trim()) }
    }

    fun refreshCredits() {
        viewModelScope.launch {
            _state.update { it.copy(creditState = creditsClient.refresh()) }
        }
    }

    fun exportArchive() {
        viewModelScope.launch {
            _state.update { it.copy(exportedFile = exporter.exportArchiveZip()) }
        }
    }
}
