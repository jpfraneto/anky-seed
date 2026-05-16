package inc.anky.android.feature.you

import inc.anky.android.core.credits.CreditState
import inc.anky.android.core.privacy.PrivacyMessages
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

class YouViewModelStateTest {
    @Test
    fun mergeRefreshedStatePreservesTransientUiFields() {
        val exportedFile = File("anky-backup.zip")
        val previous = YouState(
            publicKey = "old-key",
            recoveryPhrase = "able about above absent",
            purchasingCreditPackageId = "inc.dev.anky.credits.22",
            exportedFile = exportedFile,
            statusMessage = "exported backup.",
            error = "previous error",
        )
        val refreshed = YouState(
            publicKey = "new-key",
            creditState = CreditState(isConfigured = true, balance = 7, message = "credits refreshed."),
            localAnkyFileCount = 2,
            completeAnkyCount = 1,
            totalWritingMinutes = 9,
            currentStreak = 3,
            reflectionCount = 1,
        )

        val merged = mergeRefreshedYouState(previous, refreshed)

        assertEquals("new-key", merged.publicKey)
        assertEquals(7, merged.creditState.balance)
        assertEquals(2, merged.localAnkyFileCount)
        assertEquals(1, merged.completeAnkyCount)
        assertEquals(9, merged.totalWritingMinutes)
        assertEquals(3, merged.currentStreak)
        assertEquals(1, merged.reflectionCount)
        assertEquals(previous.recoveryPhrase, merged.recoveryPhrase)
        assertEquals(previous.purchasingCreditPackageId, merged.purchasingCreditPackageId)
        assertSame(exportedFile, merged.exportedFile)
        assertEquals(previous.statusMessage, merged.statusMessage)
        assertEquals(previous.error, merged.error)
    }

    @Test
    fun freeCreditMessageIncludesAndroidVersionNameAndCode() {
        val state = YouState(publicKey = "PUBLIC_KEY")
        assertEquals(
            PrivacyMessages.freeCreditMessage("PUBLIC_KEY", "${inc.anky.android.BuildConfig.VERSION_NAME} ${inc.anky.android.BuildConfig.VERSION_CODE}"),
            state.freeCreditMessage,
        )
    }

    @Test
    fun localIdentityLoadFailureShowsIosCopyAndStopsCreditLoading() {
        val failed = localIdentityLoadFailureState(
            YouState(
                publicKey = "",
                creditState = CreditState(false, null, "loading credit packs", isLoading = true),
            ),
        )

        assertEquals("Could not load the local writer identity.", failed.error)
        assertEquals(false, failed.creditState.isLoading)
        assertEquals("no credit packs available", failed.creditState.message)
    }

    @Test
    fun identityStatusMatchesIosDefaultWhilePublicKeyLoads() {
        assertEquals("Recovery phrase identity", identityStatus(YouState(publicKey = "")))
        assertEquals("Recovery phrase identity", identityStatus(YouState(publicKey = "PUBLIC_KEY")))
    }

    @Test
    fun creditLoadFailureStateMatchesIosCopy() {
        val failed = creditLoadFailureState()

        assertEquals(false, failed.isConfigured)
        assertEquals(null, failed.balance)
        assertEquals("Could not load credits.", failed.message)
        assertEquals(false, failed.isLoading)
    }

    @Test
    fun exportBackupActionMatchesIosPreparedFileState() {
        assertEquals(
            ExportBackupAction.Empty,
            exportBackupAction(YouState(localAnkyFileCount = 3, reflectionCount = 2, exportedFile = null)),
        )
        assertEquals(
            ExportBackupAction.Share,
            exportBackupAction(YouState(exportedFile = File("anky-backup.zip"))),
        )
    }

    @Test
    fun statusCopyMatchesIosSentenceCasing() {
        assertEquals("Recovery phrase imported.", YouStatusCopy.RecoveryPhraseImported)
        assertEquals("Map index repaired.", YouStatusCopy.MapIndexRepaired)
        assertEquals("Local reflections cleared.", YouStatusCopy.LocalReflectionsCleared)
        assertEquals("Local .anky archive cleared.", YouStatusCopy.LocalAnkyArchiveCleared)
        assertEquals("Local writing data cleared.", YouStatusCopy.LocalWritingDataCleared)
        assertEquals("Local identity reset.", YouStatusCopy.LocalIdentityReset)
        assertEquals("Could not create a backup zip.", YouStatusCopy.CouldNotCreateBackupZip)
        assertEquals("Could not load the local writer identity.", YouStatusCopy.CouldNotLoadLocalWriterIdentity)
        assertEquals("Could not load the recovery phrase.", YouStatusCopy.CouldNotLoadRecoveryPhrase)
        assertEquals("Could not schedule the daily reminder.", YouStatusCopy.CouldNotScheduleDailyReminder)
        assertEquals("Could not load credits.", YouStatusCopy.CouldNotLoadCredits)
    }
}
