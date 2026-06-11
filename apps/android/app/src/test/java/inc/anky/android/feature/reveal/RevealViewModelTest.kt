package inc.anky.android.feature.reveal

import android.app.Activity
import inc.anky.android.core.credits.CreditPackage
import inc.anky.android.core.credits.CreditState
import inc.anky.android.core.credits.CreditsClient
import inc.anky.android.core.credits.ReflectionCreditCache
import inc.anky.android.core.identity.WriterIdentity
import inc.anky.android.core.mirror.MirrorClient
import inc.anky.android.core.mirror.MirrorConfiguration
import inc.anky.android.core.mirror.ReflectionCreditPromptState
import inc.anky.android.core.storage.LocalAnkyArchive
import inc.anky.android.core.storage.LocalReflection
import inc.anky.android.core.storage.ReflectionRequestStore
import inc.anky.android.core.storage.ReflectionStore
import inc.anky.android.core.storage.SessionIndexStore
import java.io.File
import java.time.Instant
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

@OptIn(ExperimentalCoroutinesApi::class)
class RevealViewModelTest {
    @get:Rule val temp = TemporaryFolder()

    @Test
    fun mirrorThreadProgressMatchesIosMonotonicCap() {
        assertEquals(0.08f, mirrorThreadProgress(0), 0.0001f)
        assertTrue(mirrorThreadProgress(1000) > mirrorThreadProgress(500))
        assertTrue(mirrorThreadProgress(2400) > mirrorThreadProgress(1000))
        assertEquals(0.92f, mirrorThreadProgress(10_000), 0.0001f)
        assertEquals(1f, mirrorThreadProgress(10_000, isComplete = true), 0.0001f)
    }

    @Test
    fun markdownHorizontalRulesMatchIos() {
        listOf("---", "***", "___", "—", "--", "__").forEach { rule ->
            assertTrue(isMarkdownHorizontalRule(rule))
        }
        listOf("", "------", "- body", "truth").forEach { text ->
            assertFalse(isMarkdownHorizontalRule(text))
        }
    }

    @Test
    fun progressMessagesMatchCurrentIosStages() {
        assertEquals("opening the mirror...", progressMessage("stream_open"))
        assertEquals("received your writing...", progressMessage("request_received"))
        assertEquals("reading your .anky...", progressMessage("dot_anky_read"))
        assertEquals("preparing your writing...", progressMessage("hash_computed"))
        assertEquals("opening the way...", progressMessage("identity_verified"))
        assertEquals("validating the ritual...", progressMessage("protocol_validated"))
        assertEquals("checking reflection access...", progressMessage("credit_checked"))
        assertEquals("preparing the reflection...", progressMessage("reflection_prepared"))
        assertEquals("anky is writing...", progressMessage("provider_started"))
        assertEquals("bringing it back...", progressMessage("provider_finished"))
        assertEquals("settling...", progressMessage("credit_spent"))
        assertEquals("checking payment options...", progressMessage("x402_quote_created"))
        assertEquals("payment verified...", progressMessage("x402_verified"))
        assertEquals("settling...", progressMessage("x402_settled"))
        assertEquals("no credit spent...", progressMessage("credit_not_spent"))
        assertEquals("opening the scroll...", progressMessage("complete"))
        assertEquals("server fallback", progressMessage("unknown_stage", "server fallback"))
        assertEquals("anky is working...", progressMessage("unknown_stage"))
    }

    @Test
    fun askAnkyDoesNotUploadWhenReflectionAlreadyExists() = runTest {
        val stores = stores()
        val artifact = stores.archive.save(completeAnky())
        stores.reflections.save(
            LocalReflection(
                hash = artifact.hash,
                title = "Existing Thread",
                reflection = "Already reflected.",
                createdAt = Instant.EPOCH,
                creditsRemaining = 3,
            ),
        )
        var identityLoadCount = 0
        var mirrorClientBuildCount = 0

        val viewModel = RevealViewModel(
            hash = artifact.hash,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            identityProvider = {
                identityLoadCount += 1
                identity()
            },
            mirrorClientProvider = {
                mirrorClientBuildCount += 1
                error("Mirror client should not be created for an existing reflection.")
            },
            dispatcher = StandardTestDispatcher(testScheduler),
        )

        viewModel.askAnky()
        advanceUntilIdle()

        assertFalse(viewModel.state.value.canAskAnky)
        assertFalse(viewModel.state.value.isAsking)
        assertEquals(0, identityLoadCount)
        assertEquals(0, mirrorClientBuildCount)
    }

    @Test
    fun askAnkyDoubleTapUploadsOnlyOnce() = runTest {
        val server = MockWebServer()
        val stores = stores()
        val artifact = stores.archive.save(completeAnky())
        stores.index.rebuild(stores.archive, stores.reflections)
        server.enqueue(reflectionResponse(artifact.hash))
        server.enqueue(reflectionResponse(artifact.hash))
        server.start()
        try {
            val viewModel = RevealViewModel(
                hash = artifact.hash,
                archive = stores.archive,
                reflectionStore = stores.reflections,
                requestStore = stores.requests,
                indexStore = stores.index,
                identityProvider = { identity() },
                mirrorClientProvider = { MirrorClient(MirrorConfiguration(server.url("/").toString())) },
                dispatcher = StandardTestDispatcher(testScheduler),
            )

            assertTrue(viewModel.state.value.canAskAnky)
            viewModel.askAnky()
            viewModel.askAnky()

            assertTrue(viewModel.state.value.isAsking)
            advanceUntilIdle()

            assertEquals(1, server.requestCount)
            assertFalse(viewModel.state.value.canAskAnky)
            assertFalse(viewModel.state.value.isAsking)
            assertNotNull(stores.reflections.load(artifact.hash))
            assertEquals("Small Thread", stores.index.load().single().reflectionTitle)
            assertEquals(listOf("truth", "body"), stores.index.load().single().tags)
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun askAnkyDoesNotExposeRawUnexpectedErrors() = runTest {
        val stores = stores()
        val artifact = stores.archive.save(completeAnky())

        val viewModel = RevealViewModel(
            hash = artifact.hash,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            identityProvider = { identity() },
            mirrorClientProvider = { error("raw transport detail") },
            dispatcher = StandardTestDispatcher(testScheduler),
        )

        viewModel.askAnky()
        advanceUntilIdle()

        assertFalse(viewModel.state.value.isAsking)
        assertEquals("Anky could not return a reflection right now.", viewModel.state.value.error)
    }

    @Test
    fun askAnkyRejectsMismatchedResponseHashLikeIos() = runTest {
        val server = MockWebServer()
        val stores = stores()
        val artifact = stores.archive.save(completeAnky())
        stores.index.rebuild(stores.archive, stores.reflections)
        server.enqueue(reflectionResponse("b".repeat(64)))
        server.start()
        try {
            val viewModel = RevealViewModel(
                hash = artifact.hash,
                archive = stores.archive,
                reflectionStore = stores.reflections,
                indexStore = stores.index,
                identityProvider = { identity() },
                mirrorClientProvider = { MirrorClient(MirrorConfiguration(server.url("/").toString())) },
                dispatcher = StandardTestDispatcher(testScheduler),
            )

            viewModel.askAnky()
            advanceUntilIdle()

            assertFalse(viewModel.state.value.isAsking)
            assertTrue(viewModel.state.value.canAskAnky)
            assertEquals("The mirror response did not match this .anky.", viewModel.state.value.error)
            assertEquals(null, stores.reflections.load(artifact.hash))
            assertFalse(stores.index.load().single().hasReflection)
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun askAnkyStoresCreditsRemainingAndInvalidatesCreditCache() = runTest {
        val server = MockWebServer()
        val stores = stores()
        val credits = FakeCreditsClient(balance = 9)
        val creditCache = FakeReflectionCreditCache()
        val artifact = stores.archive.save(completeAnky())
        stores.index.rebuild(stores.archive, stores.reflections)
        server.enqueue(reflectionResponse(artifact.hash, creditsRemaining = 7))
        server.start()
        try {
            val viewModel = RevealViewModel(
                hash = artifact.hash,
                archive = stores.archive,
                reflectionStore = stores.reflections,
                indexStore = stores.index,
                identityProvider = { identity() },
                mirrorClientProvider = { MirrorClient(MirrorConfiguration(server.url("/").toString())) },
                creditsClient = credits,
                reflectionCreditCache = creditCache,
                dispatcher = StandardTestDispatcher(testScheduler),
            )

            viewModel.askAnky()
            advanceUntilIdle()

            assertEquals(7, stores.reflections.load(artifact.hash)?.creditsRemaining)
            assertEquals(listOf("truth", "body"), stores.reflections.load(artifact.hash)?.tags)
            assertFalse(stores.requests.isPending(artifact.hash))
            assertEquals(7, viewModel.state.value.creditBalance)
            assertEquals(7, creditCache.balance(identity().accountId))
            assertTrue(viewModel.state.value.hasClaimedFreeCredits)
            assertEquals(1, credits.invalidateCount)
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun askAnkyStreamsProgressAndKeepsFinalStreamAfterSaveLikeIos() = runTest {
        val server = MockWebServer()
        val stores = stores()
        val artifact = stores.archive.save(completeAnky())
        stores.index.rebuild(stores.archive, stores.reflections)
        server.enqueue(streamingReflectionResponse(artifact.hash))
        server.start()
        try {
            val viewModel = RevealViewModel(
                hash = artifact.hash,
                archive = stores.archive,
                reflectionStore = stores.reflections,
                indexStore = stores.index,
                identityProvider = { identity() },
                mirrorClientProvider = { MirrorClient(MirrorConfiguration(server.url("/").toString())) },
                dispatcher = StandardTestDispatcher(testScheduler),
            )

            viewModel.askAnky()
            advanceUntilIdle()

            assertFalse(viewModel.state.value.isAsking)
            assertEquals(viewModel.state.value.reflection?.reflection, viewModel.state.value.streamingReflectionMarkdown)
            assertEquals(null, viewModel.state.value.progressStage)
            assertEquals("Small Thread", viewModel.state.value.reflection?.title)
            assertEquals(listOf("truth", "body"), viewModel.state.value.reflection?.tags)
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun claimedFreeCreditsWithoutBalanceBlocksReflectionUntilCreditsLoadLikeIos() = runTest {
        val stores = stores()
        val artifact = stores.archive.save(completeAnky())
        val viewModel = RevealViewModel(
            hash = artifact.hash,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            identityProvider = { identity() },
            mirrorClientProvider = { error("Ask Anky should be blocked with no reflections left.") },
            hasClaimedFreeCreditsProvider = { true },
            dispatcher = StandardTestDispatcher(testScheduler),
        )

        advanceUntilIdle()

        assertEquals(ReflectionCreditPromptState.Unavailable, viewModel.state.value.creditPromptState)
        assertEquals("No reflections left", viewModel.state.value.creditPromptMessage)
        assertFalse(viewModel.state.value.canSubmitReflectionRequest)
        assertTrue(viewModel.state.value.needsCreditsToReflect)
        viewModel.askAnky()
        advanceUntilIdle()
        assertFalse(viewModel.state.value.isAsking)
    }

    @Test
    fun refreshCreditsConfiguresIdentityAndUpdatesRevealBalanceLikeIos() = runTest {
        val stores = stores()
        val artifact = stores.archive.save(completeAnky())
        val credits = FakeCreditsClient(balance = 2)
        val creditCache = FakeReflectionCreditCache()
        val viewModel = RevealViewModel(
            hash = artifact.hash,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            identityProvider = { identity() },
            mirrorClientProvider = { error("Refreshing credits should not ask the mirror.") },
            creditsClient = credits,
            reflectionCreditCache = creditCache,
            hasClaimedFreeCreditsProvider = { true },
            dispatcher = StandardTestDispatcher(testScheduler),
        )

        viewModel.refreshCredits()
        advanceUntilIdle()

        assertEquals(identity().accountId, credits.configuredAppUserId)
        assertEquals(2, viewModel.state.value.creditBalance)
        assertEquals(2, creditCache.balance(identity().accountId))
        assertEquals(credits.packages, viewModel.state.value.creditPackages)
        assertFalse(viewModel.state.value.creditsDenied)
        assertFalse(viewModel.state.value.creditsLoading)
    }

    @Test
    fun unavailableCreditStateOpensPurchasePathInsteadOfReflectionSubmit() = runTest {
        val stores = stores()
        val artifact = stores.archive.save(completeAnky())
        val viewModel = RevealViewModel(
            hash = artifact.hash,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            identityProvider = { identity() },
            mirrorClientProvider = { error("Get more credits should not ask the mirror.") },
            hasClaimedFreeCreditsProvider = { true },
            dispatcher = StandardTestDispatcher(testScheduler),
        )

        viewModel.refreshCredits()
        advanceUntilIdle()
        viewModel.askAnky()
        advanceUntilIdle()

        assertEquals(ReflectionCreditPromptState.Unavailable, viewModel.state.value.creditPromptState)

        val denied = viewModel.state.value.copy(creditBalance = 0, creditsDenied = true)
        assertFalse(denied.canSubmitReflectionRequest)
        assertTrue(denied.needsCreditsToReflect)
    }

    @Test
    fun purchaseCreditsRefreshesRevealBalanceAndPackages() = runTest {
        val stores = stores()
        val artifact = stores.archive.save(completeAnky())
        val credits = FakeCreditsClient(
            balance = 0,
            purchaseBalance = 3,
            packages = listOf(CreditPackage("inc.anky.credits.3", "inc.anky.credits.3", "3 reflections", "starter", "$2.99")),
        )
        val creditCache = FakeReflectionCreditCache()
        val viewModel = RevealViewModel(
            hash = artifact.hash,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            identityProvider = { identity() },
            mirrorClientProvider = { error("Purchasing credits should not ask the mirror.") },
            creditsClient = credits,
            reflectionCreditCache = creditCache,
            hasClaimedFreeCreditsProvider = { true },
            dispatcher = StandardTestDispatcher(testScheduler),
        )

        viewModel.purchaseCredits("inc.anky.credits.3", null)
        advanceUntilIdle()

        assertEquals(identity().accountId, credits.configuredAppUserId)
        assertEquals("inc.anky.credits.3", credits.purchasedPackageId)
        assertEquals(3, viewModel.state.value.creditBalance)
        assertEquals(3, creditCache.balance(identity().accountId))
        assertEquals(credits.packages, viewModel.state.value.creditPackages)
        assertFalse(viewModel.state.value.creditsDenied)
        assertEquals(null, viewModel.state.value.purchasingCreditPackageId)
    }

    @Test
    fun askAnkyCreditFailureMarksCreditsDenied() = runTest {
        val server = MockWebServer()
        val stores = stores()
        val artifact = stores.archive.save(completeAnky())
        server.enqueue(
            MockResponse()
                .setResponseCode(402)
                .setBody("""{"error":{"code":"INSUFFICIENT_CREDITS","message":"You need one credit to ask Anky for a reflection."}}"""),
        )
        server.start()
        try {
            val creditCache = FakeReflectionCreditCache().apply {
                storeBalance(1, identity().accountId)
            }
            val viewModel = RevealViewModel(
                hash = artifact.hash,
                archive = stores.archive,
                reflectionStore = stores.reflections,
                indexStore = stores.index,
                identityProvider = { identity() },
                mirrorClientProvider = { MirrorClient(MirrorConfiguration(server.url("/").toString())) },
                reflectionCreditCache = creditCache,
                hasClaimedFreeCreditsProvider = { true },
                dispatcher = StandardTestDispatcher(testScheduler),
            )

            viewModel.askAnky()
            advanceUntilIdle()

            assertEquals(0, viewModel.state.value.creditBalance)
            assertTrue(viewModel.state.value.creditsDenied)
            assertEquals(ReflectionCreditPromptState.Unavailable, viewModel.state.value.creditPromptState)
            assertEquals(
                "You need one reflection credit to ask Anky. Writing is still free.",
                viewModel.state.value.error,
            )
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun askAnkyTrialAlreadyClaimedShowsDeviceGiftCopyLikeIos() = runTest {
        val server = MockWebServer()
        val stores = stores()
        val artifact = stores.archive.save(completeAnky())
        server.enqueue(
            MockResponse()
                .setResponseCode(402)
                .setBody("""{"error":{"code":"TRIAL_ALREADY_CLAIMED","message":"Trial already claimed."}}"""),
        )
        server.start()
        try {
            var markedClaimed = false
            val viewModel = RevealViewModel(
                hash = artifact.hash,
                archive = stores.archive,
                reflectionStore = stores.reflections,
                indexStore = stores.index,
                identityProvider = { identity() },
                mirrorClientProvider = { MirrorClient(MirrorConfiguration(server.url("/").toString())) },
                hasClaimedFreeCreditsProvider = { false },
                markFreeCreditsClaimed = { markedClaimed = true },
                dispatcher = StandardTestDispatcher(testScheduler),
            )

            viewModel.askAnky()
            advanceUntilIdle()

            assertEquals(0, viewModel.state.value.creditBalance)
            assertTrue(viewModel.state.value.creditsDenied)
            assertTrue(viewModel.state.value.hasClaimedFreeCredits)
            assertTrue(markedClaimed)
            assertEquals(
                "This device already used its first two reflections. Add credits to ask Anky again. Writing is still free.",
                viewModel.state.value.error,
            )
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun askAnkyDoesNotInvalidateCreditCacheWhenCreditsRemainingIsNull() = runTest {
        val server = MockWebServer()
        val stores = stores()
        val credits = FakeCreditsClient(balance = 9)
        val artifact = stores.archive.save(completeAnky())
        stores.index.rebuild(stores.archive, stores.reflections)
        server.enqueue(reflectionResponse(artifact.hash, creditsRemaining = null))
        server.start()
        try {
            val viewModel = RevealViewModel(
                hash = artifact.hash,
                archive = stores.archive,
                reflectionStore = stores.reflections,
                indexStore = stores.index,
                identityProvider = { identity() },
                mirrorClientProvider = { MirrorClient(MirrorConfiguration(server.url("/").toString())) },
                creditsClient = credits,
                dispatcher = StandardTestDispatcher(testScheduler),
            )

            viewModel.askAnky()
            advanceUntilIdle()

            assertEquals(null, stores.reflections.load(artifact.hash)?.creditsRemaining)
            assertEquals(0, credits.invalidateCount)
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun revealSeedsCreditBalanceFromPerAccountCacheLikeIos() = runTest {
        val stores = stores()
        val artifact = stores.archive.save(completeAnky())
        val creditCache = FakeReflectionCreditCache().apply {
            storeBalance(6, identity().accountId)
        }

        val viewModel = RevealViewModel(
            hash = artifact.hash,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            identityProvider = { identity() },
            mirrorClientProvider = { error("Cached credit load should not ask the mirror.") },
            reflectionCreditCache = creditCache,
            hasClaimedFreeCreditsProvider = { true },
            dispatcher = StandardTestDispatcher(testScheduler),
        )

        assertEquals(6, viewModel.state.value.creditBalance)
        assertEquals(ReflectionCreditPromptState.Available(6), viewModel.state.value.creditPromptState)
    }

    @Test
    fun copyTextIsSectionAwareAndReflectionIncludesTitleAndBody() = runTest {
        val stores = stores()
        val artifact = stores.archive.save(completeAnky())
        stores.reflections.save(
            LocalReflection(
                hash = artifact.hash,
                title = "Small Thread",
                reflection = "Here is what I saw.",
                createdAt = Instant.EPOCH,
                creditsRemaining = 3,
            ),
        )
        val viewModel = RevealViewModel(
            hash = artifact.hash,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            identityProvider = { identity() },
            mirrorClientProvider = { error("Copy should not ask the mirror.") },
            dispatcher = StandardTestDispatcher(testScheduler),
        )

        assertEquals("hello!", viewModel.textForCopy(RevealCopySection.Writing))
        assertEquals("Small Thread\n\nHere is what I saw.", viewModel.textForCopy(RevealCopySection.Reflection))
        assertTrue(viewModel.textForCopy(RevealCopySection.ReflectionPrompt)?.contains("---\n\nhello!") == true)

        viewModel.markCopied(RevealCopySection.Writing)
        assertEquals(RevealCopySection.Writing, viewModel.state.value.copiedSection)
        viewModel.clearCopied(RevealCopySection.Reflection)
        assertEquals(RevealCopySection.Writing, viewModel.state.value.copiedSection)
        viewModel.clearCopied(RevealCopySection.Writing)
        assertEquals(null, viewModel.state.value.copiedSection)
    }

    @Test
    fun deleteSessionRemovesLocalArchiveReflectionAndIndexOnly() = runTest {
        val stores = stores()
        val artifact = stores.archive.save(completeAnky())
        stores.reflections.save(
            LocalReflection(
                hash = artifact.hash,
                title = "Small Thread",
                reflection = "Here is what I saw.",
                createdAt = Instant.EPOCH,
                creditsRemaining = 3,
            ),
        )
        stores.index.rebuild(stores.archive, stores.reflections)
        val viewModel = RevealViewModel(
            hash = artifact.hash,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            indexStore = stores.index,
            identityProvider = { identity() },
            mirrorClientProvider = { error("Delete should not create a mirror client.") },
            dispatcher = StandardTestDispatcher(testScheduler),
        )

        viewModel.deleteSession()
        advanceUntilIdle()

        assertTrue(viewModel.state.value.isDeleted)
        assertEquals(null, stores.reflections.load(artifact.hash))
        assertTrue(stores.index.load().isEmpty())
        assertFalse(artifact.file.exists())
    }

    private fun stores(): Stores {
        val root = temp.newFolder()
        return Stores(
            archive = LocalAnkyArchive.forDirectory(File(root, "archive")),
            reflections = ReflectionStore.forDirectory(File(root, "reflections")),
            requests = ReflectionRequestStore.forFile(File(root, "pending-reflection-requests.json")),
            index = SessionIndexStore.forFile(File(root, "session-index.json")),
        )
    }

    private fun completeAnky(): String =
        "1770000000000 h\n100000 e\n100000 l\n100000 l\n100000 o\n80000 !\n8000"

    private fun identity(): WriterIdentity =
        WriterIdentity.fromRecoveryPhrase(
            inc.anky.android.core.identity.RecoveryPhrase.parse(
                "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
            ),
        )

    private fun reflectionResponse(hash: String, creditsRemaining: Int? = 3): MockResponse =
        MockResponse()
            .setResponseCode(200)
            .setHeader("Content-Type", "text/markdown; charset=utf-8")
            .setHeader("X-Anky-Hash", hash)
            .setHeader("X-Anky-Credits-Remaining", creditsRemaining?.toString() ?: "null")
            .setHeader("X-Anky-Tags", """["truth","body"]""")
            .setBody("# Small Thread\n\nHere is what I saw.")

    private fun streamingReflectionResponse(hash: String): MockResponse =
        MockResponse()
            .setResponseCode(200)
            .setHeader("Content-Type", "text/event-stream")
            .setBody(
                """
                event: update
                data: {"stage":"provider_started","message":"writing"}

                event: reflection_chunk
                data: {"chunk":"# Small","generatedCharacters":7}

                event: reflection_chunk
                data: {"chunk":" Thread","generatedCharacters":14}

                event: reflection
                data: {"markdown":"# Small Thread\n\nHere is what I saw.","tags":["truth","body"],"headers":{"X-Anky-Hash":"$hash","X-Anky-Credits-Remaining":"4"}}

                """.trimIndent(),
            )

    private data class Stores(
        val archive: LocalAnkyArchive,
        val reflections: ReflectionStore,
        val requests: ReflectionRequestStore,
        val index: SessionIndexStore,
    )

    private class FakeCreditsClient(
        private val balance: Int?,
        private val purchaseBalance: Int? = balance,
        val packages: List<CreditPackage> = emptyList(),
    ) : CreditsClient {
        var configuredAppUserId: String? = null
        var invalidateCount = 0
        var purchasedPackageId: String? = null

        override suspend fun configure(appUserId: String) {
            configuredAppUserId = appUserId
        }

        override suspend fun refresh(): CreditState =
            CreditState(isConfigured = true, balance = balance, message = "credits refreshed.", packages = packages)

        override suspend fun purchase(packageId: String, activity: Activity?): CreditState {
            purchasedPackageId = packageId
            return CreditState(isConfigured = true, balance = purchaseBalance, message = "Credits updated.", packages = packages)
        }

        override suspend fun restorePurchases(): CreditState =
            refresh()

        override suspend fun invalidateCreditBalanceCache() {
            invalidateCount += 1
        }

        override suspend fun logOutIfConfigured() = Unit
    }

    private class FakeReflectionCreditCache : ReflectionCreditCache {
        private val balances = mutableMapOf<String, Int>()
        private val claimedAccountIds = mutableSetOf<String>()

        override fun hasClaimedFreeCredits(accountId: String): Boolean =
            claimedAccountIds.contains(accountId)

        override fun markFreeCreditsClaimed(accountId: String) {
            claimedAccountIds += accountId
        }

        override fun balance(accountId: String): Int? =
            balances[accountId]

        override fun storeBalance(balance: Int?, accountId: String) {
            if (balance == null) {
                balances.remove(accountId)
            } else {
                balances[accountId] = balance
            }
        }

        override fun clear() {
            balances.clear()
            claimedAccountIds.clear()
        }
    }
}
