package inc.anky.android.app

import android.content.Context
import inc.anky.android.core.credits.CreditsClient
import inc.anky.android.core.credits.RevenueCatCreditsClient
import inc.anky.android.core.identity.WriterIdentityStore
import inc.anky.android.core.mirror.MirrorClient
import inc.anky.android.core.mirror.MirrorConfiguration
import inc.anky.android.core.notifications.DailyReminderScheduler
import inc.anky.android.core.storage.ActiveDraftStore
import inc.anky.android.core.storage.AppOpenStore
import inc.anky.android.core.storage.BackupImporter
import inc.anky.android.core.storage.Exporter
import inc.anky.android.core.storage.LocalAnkyArchive
import inc.anky.android.core.storage.ReflectionStore
import inc.anky.android.core.storage.SessionIndexStore

class AppContainer(
    context: Context,
) {
    private val appContext = context.applicationContext

    val identityStore = WriterIdentityStore(appContext)
    val activeDraftStore = ActiveDraftStore(appContext)
    val archive = LocalAnkyArchive(appContext)
    val reflectionStore = ReflectionStore(appContext)
    val sessionIndexStore = SessionIndexStore(appContext)
    val appOpenStore = AppOpenStore(appContext)
    val settingsStore = UserSettingsStore(appContext)
    val reminderScheduler = DailyReminderScheduler(appContext)
    val creditsClient: CreditsClient = RevenueCatCreditsClient(appContext)
    val exporter = Exporter(appContext, archive, reflectionStore)
    val backupImporter = BackupImporter(
        appContext,
        archive,
        reflectionStore,
        sessionIndexStore,
        recordEarlierFirstOpenDate = { appOpenStore.recordEarlierFirstOpenDate(it) },
    )

    fun mirrorClient(baseUrl: String): MirrorClient =
        MirrorClient(MirrorConfiguration(baseUrl = baseUrl))
}
