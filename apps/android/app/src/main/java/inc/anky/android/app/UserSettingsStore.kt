package inc.anky.android.app

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import inc.anky.android.BuildConfig
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

data class UserSettings(
    val appLockEnabled: Boolean = false,
    val dailyReminderEnabled: Boolean = false,
    val mirrorBaseUrl: String = BuildConfig.DEFAULT_MIRROR_BASE_URL,
)

private val Context.ankySettings by preferencesDataStore(name = "anky-settings")

class UserSettingsStore(
    private val context: Context,
) {
    val settings: Flow<UserSettings> =
        context.ankySettings.data.map { preferences ->
            UserSettings(
                appLockEnabled = preferences[AppLockEnabled] ?: false,
                dailyReminderEnabled = preferences[DailyReminderEnabled] ?: false,
                mirrorBaseUrl = preferences[MirrorBaseUrl] ?: BuildConfig.DEFAULT_MIRROR_BASE_URL,
            )
        }

    suspend fun setAppLockEnabled(enabled: Boolean) {
        context.ankySettings.edit { it[AppLockEnabled] = enabled }
    }

    suspend fun setDailyReminderEnabled(enabled: Boolean) {
        context.ankySettings.edit { it[DailyReminderEnabled] = enabled }
    }

    suspend fun setMirrorBaseUrl(url: String) {
        context.ankySettings.edit { it[MirrorBaseUrl] = url }
    }

    companion object {
        private val AppLockEnabled = booleanPreferencesKey("app_lock_enabled")
        private val DailyReminderEnabled = booleanPreferencesKey("daily_reminder_enabled")
        private val MirrorBaseUrl = stringPreferencesKey("mirror_base_url")
    }
}
