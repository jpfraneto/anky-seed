package inc.anky.android.feature.you

import inc.anky.android.core.credits.CreditState
import inc.anky.android.core.credits.cachedCreditState
import inc.anky.android.core.privacy.PrivacyMessages
import inc.anky.android.core.storage.SessionSummary
import java.io.File
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class YouViewModelStateTest {
    @Test
    fun mergeRefreshedStatePreservesTransientUiFields() {
        val exportedFile = File("anky-backup.zip")
        val formattedWritingExportFile = File("anky-writings.md")
        val previous = YouState(
            accountId = "old-key",
            recoveryPhrase = "able about above absent",
            purchasingCreditPackageId = "inc.anky.credits.3",
            isRestoringPurchases = true,
            exportedFile = exportedFile,
            formattedWritingExportFile = formattedWritingExportFile,
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
            completeAnkySessions = listOf(summary(hash = "b".repeat(64), createdAt = Instant.EPOCH.plusSeconds(60))),
        )

        val merged = mergeRefreshedYouState(previous, refreshed)

        assertEquals("new-key", merged.accountId)
        assertEquals(7, merged.creditState.balance)
        assertEquals(2, merged.localAnkyFileCount)
        assertEquals(1, merged.completeAnkyCount)
        assertEquals(9, merged.totalWritingMinutes)
        assertEquals(3, merged.currentStreak)
        assertEquals(1, merged.reflectionCount)
        assertEquals(refreshed.completeAnkySessions, merged.completeAnkySessions)
        assertEquals(previous.recoveryPhrase, merged.recoveryPhrase)
        assertEquals(previous.purchasingCreditPackageId, merged.purchasingCreditPackageId)
        assertEquals(previous.isRestoringPurchases, merged.isRestoringPurchases)
        assertSame(exportedFile, merged.exportedFile)
        assertSame(formattedWritingExportFile, merged.formattedWritingExportFile)
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
    fun supportFeedbackEmailUrlMatchesIosMailtoShape() {
        val state = YouState(accountId = "0x9858EfFD232B4033E47d90003D41EC34EcaEda94")

        assertTrue(state.supportFeedbackEmailUrl.startsWith("mailto:support@anky.app?"))
        assertTrue(state.supportFeedbackEmailUrl.contains("subject=Anky%20support%20%2F%20feedback"))
        assertTrue(state.supportFeedbackEmailUrl.contains("body=account%20id%3A%200x9858EfFD232B4033E47d90003D41EC34EcaEda94"))
    }

    @Test
    fun localIdentityLoadFailureShowsIosCopyAndStopsCreditLoading() {
        val failed = localIdentityLoadFailureState(
            YouState(
                accountId = "",
                creditState = CreditState(false, null, "loading credit packs", isLoading = true),
            ),
        )

        assertEquals("Could not load the local Base identity.", failed.error)
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
    fun unspentGiftCreditPresentationMatchesIosGate() {
        val giftState = YouState(
            creditState = CreditState(isConfigured = true, balance = 9, message = "credits refreshed."),
            hasClaimedFreeCredits = false,
        )
        val claimedState = giftState.copy(hasClaimedFreeCredits = true)

        assertEquals(9, giftState.presentedCreditBalance)
        assertEquals(false, giftState.hasUnspentGiftCredit)
        assertEquals(true, giftState.canPurchaseCredits)
        assertEquals("9", giftState.creditDetailTitle)
        assertEquals("credits", giftState.creditDetailCaption)
        assertEquals(9, claimedState.presentedCreditBalance)
        assertEquals(false, claimedState.hasUnspentGiftCredit)
        assertEquals(true, claimedState.canPurchaseCredits)
        assertEquals("9", claimedState.creditDetailTitle)
        assertEquals("credits", claimedState.creditDetailCaption)
    }

    @Test
    fun deniedDeviceGiftDoesNotResurrectStaleFirstGiftBalance() {
        val refreshed = CreditState(isConfigured = true, balance = 2, message = "credits refreshed.")

        val normalized = refreshed.afterDeviceGiftDenialGate(
            cachedBalance = 0,
            hasClaimedFreeCredits = true,
        )

        assertEquals(0, normalized.balance)
        assertEquals(2, refreshed.afterDeviceGiftDenialGate(cachedBalance = 2, hasClaimedFreeCredits = true).balance)
        assertEquals(2, refreshed.afterDeviceGiftDenialGate(cachedBalance = 0, hasClaimedFreeCredits = false).balance)
    }

    @Test
    fun cachedCreditStateSeedsYouCreditBalanceLikeIos() {
        val cached = cachedCreditState(5)

        assertEquals(true, cached?.isConfigured)
        assertEquals(5, cached?.balance)
        assertEquals("credits refreshed.", cached?.message)
        assertEquals(false, cached?.isLoading)
        assertEquals(null, cachedCreditState(null))
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
    fun formattedWritingExportActionMatchesIosPreparedFileState() {
        assertEquals(
            FormattedWritingExportAction.Empty,
            formattedWritingExportAction(YouState(localAnkyFileCount = 3, formattedWritingExportFile = null)),
        )
        assertEquals(
            FormattedWritingExportAction.Share,
            formattedWritingExportAction(YouState(formattedWritingExportFile = File("anky-writings.md"))),
        )
    }

    @Test
    fun completeAnkySessionsAreSortedNewestFirstForYouHistory() {
        val older = summary(hash = "a".repeat(64), createdAt = Instant.EPOCH.plusSeconds(1))
        val newer = summary(hash = "b".repeat(64), createdAt = Instant.EPOCH.plusSeconds(2))
        val state = YouState(
            completeAnkyCount = 2,
            completeAnkySessions = listOf(newer, older),
        )

        assertEquals(listOf(newer, older), state.completeAnkySessions)
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
        assertEquals("Could not create a writing export.", YouStatusCopy.CouldNotCreateWritingExport)
        assertEquals("There is no writing to export yet.", YouStatusCopy.NoWritingToExportYet)
        assertEquals("Could not load the local Base identity.", YouStatusCopy.CouldNotLoadLocalWriterIdentity)
        assertEquals("Could not load the recovery words.", YouStatusCopy.CouldNotLoadRecoveryPhrase)
        assertEquals("Recovery words saved to device secure storage. Use Data export for writing and reflection backups.", YouStatusCopy.IdentityBackupSaved)
        assertEquals("Could not back up Anky identity.", YouStatusCopy.CouldNotBackUpAnkyIdentity)
        assertEquals("Could not schedule the daily reminder.", YouStatusCopy.CouldNotScheduleDailyReminder)
        assertEquals("Could not load credits.", YouStatusCopy.CouldNotLoadCredits)
        assertEquals("Account and data deleted from this device.", YouStatusCopy.AccountAndDataDeleted)
        assertEquals("Could not delete all account data.", YouStatusCopy.CouldNotDeleteAllAccountData)
    }

    @Test
    fun recoveryImportValidationCopyMatchesIosPhraseLanguage() {
        assertEquals(
            "Recovery words must be 12 words.",
            recoveryImportErrorMessage(IllegalArgumentException("Recovery phrase must contain 12 words.")),
        )
        assertEquals(
            "Recovery words contain an unrecognized word.",
            recoveryImportErrorMessage(IllegalArgumentException("Recovery phrase contains an unsupported word.")),
        )
        assertEquals(
            "Could not recover that identity.",
            recoveryImportErrorMessage(IllegalArgumentException("boom")),
        )
    }

    private fun summary(hash: String, createdAt: Instant): SessionSummary =
        SessionSummary(
            hash = hash,
            createdAt = createdAt,
            localFilePath = "/tmp/$hash.anky",
            durationMs = 480_000,
            isComplete = true,
            preview = "hello world",
            wordCount = 2,
            hasReflection = true,
            reflectionTitle = "quiet thread",
        )
}
