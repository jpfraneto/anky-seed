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
            accountId = "old-key",
            recoveryPhrase = "able about above absent",
            purchasingCreditPackageId = "inc.dev.anky.credits.22",
            isRestoringPurchases = true,
            exportedFile = exportedFile,
            statusMessage = "exported backup.",
            error = "previous error",
        )
        val refreshed = YouState(
            accountId = "new-key",
            creditState = CreditState(isConfigured = true, balance = 7, message = "credits refreshed."),
            localAnkyFileCount = 2,
            completeAnkyCount = 1,
            totalWritingMinutes = 9,
            currentStreak = 3,
            reflectionCount = 1,
        )

        val merged = mergeRefreshedYouState(previous, refreshed)

        assertEquals("new-key", merged.accountId)
        assertEquals(7, merged.creditState.balance)
        assertEquals(2, merged.localAnkyFileCount)
        assertEquals(1, merged.completeAnkyCount)
        assertEquals(9, merged.totalWritingMinutes)
        assertEquals(3, merged.currentStreak)
        assertEquals(1, merged.reflectionCount)
        assertEquals(previous.recoveryPhrase, merged.recoveryPhrase)
        assertEquals(previous.purchasingCreditPackageId, merged.purchasingCreditPackageId)
        assertEquals(previous.isRestoringPurchases, merged.isRestoringPurchases)
        assertSame(exportedFile, merged.exportedFile)
        assertEquals(previous.statusMessage, merged.statusMessage)
        assertEquals(previous.error, merged.error)
    }

    @Test
    fun freeCreditMessageIncludesAndroidVersionNameAndCode() {
        val state = YouState(accountId = "0x9858EfFD232B4033E47d90003D41EC34EcaEda94")
        assertEquals(
            PrivacyMessages.freeCreditMessage("0x9858EfFD232B4033E47d90003D41EC34EcaEda94", "${inc.anky.android.BuildConfig.VERSION_NAME} ${inc.anky.android.BuildConfig.VERSION_CODE}"),
            state.freeCreditMessage,
        )
    }

    @Test
    fun localIdentityLoadFailureShowsIosCopyAndStopsCreditLoading() {
        val failed = localIdentityLoadFailureState(
            YouState(
                accountId = "",
                creditState = CreditState(false, null, "loading credit packs", isLoading = true),
            ),
        )

        assertEquals("Could not load the local identity.", failed.error)
        assertEquals(false, failed.creditState.isLoading)
        assertEquals("no credit packs available", failed.creditState.message)
    }

    @Test
    fun identityStatusMatchesIosDefaultWhileAccountIdLoads() {
        assertEquals("Local identity", identityStatus(YouState(accountId = "")))
        assertEquals("Local identity", identityStatus(YouState(accountId = "0x9858EfFD232B4033E47d90003D41EC34EcaEda94")))
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
        assertEquals("Identity recovered.", YouStatusCopy.RecoveryPhraseImported)
        assertEquals("Map index repaired.", YouStatusCopy.MapIndexRepaired)
        assertEquals("Local reflections cleared.", YouStatusCopy.LocalReflectionsCleared)
        assertEquals("Local .anky archive cleared.", YouStatusCopy.LocalAnkyArchiveCleared)
        assertEquals("Local writing data cleared.", YouStatusCopy.LocalWritingDataCleared)
        assertEquals("Local identity reset.", YouStatusCopy.LocalIdentityReset)
        assertEquals("Could not create a backup zip.", YouStatusCopy.CouldNotCreateBackupZip)
        assertEquals("Could not load the local identity.", YouStatusCopy.CouldNotLoadLocalWriterIdentity)
        assertEquals("Could not load the recovery key.", YouStatusCopy.CouldNotLoadRecoveryPhrase)
        assertEquals("Could not schedule the daily reminder.", YouStatusCopy.CouldNotScheduleDailyReminder)
        assertEquals("Could not load credits.", YouStatusCopy.CouldNotLoadCredits)
    }
}
