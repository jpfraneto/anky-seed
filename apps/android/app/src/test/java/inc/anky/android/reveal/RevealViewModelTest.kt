package inc.anky.android.reveal

import inc.anky.android.core.identity.WriterIdentity
import inc.anky.android.core.mirror.MirrorClient
import inc.anky.android.core.mirror.MirrorClientError
import inc.anky.android.core.mirror.MirrorConfiguration
import inc.anky.android.core.mirror.MirrorErrorCode
import inc.anky.android.core.storage.LocalAnkyArchive
import inc.anky.android.core.storage.LocalReflection
import inc.anky.android.core.storage.ReflectionRequestStore
import inc.anky.android.core.storage.ReflectionStore
import inc.anky.android.core.storage.SessionIndexStore
import inc.anky.android.feature.reveal.RevealCopySection
import inc.anky.android.feature.reveal.RevealViewModel
import inc.anky.android.feature.reveal.isEntitlementDenied
import inc.anky.android.feature.reveal.isMarkdownHorizontalRule
import inc.anky.android.feature.reveal.mirrorThreadProgress
import inc.anky.android.feature.reveal.progressMessage
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

/**
 * Subscription-era reveal: entitlement gating replaces the credit economy.
 * Free (unentitled) sessions are veiled and make ZERO mirror calls.
 */
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
    fun progressMessagesMatchCurrentIosStagesWithoutCreditOrPaymentStages() {
        assertEquals("opening the mirror...", progressMessage("stream_open"))
        assertEquals("received your writing...", progressMessage("request_received"))
        assertEquals("reading your .anky...", progressMessage("dot_anky_read"))
        assertEquals("preparing your writing...", progressMessage("hash_computed"))
        assertEquals("opening the way...", progressMessage("identity_verified"))
        assertEquals("validating the ritual...", progressMessage("protocol_validated"))
        assertEquals("preparing the reflection...", progressMessage("reflection_prepared"))
        assertEquals("anky is writing...", progressMessage("provider_started"))
        assertEquals("bringing it back...", progressMessage("provider_finished"))
        assertEquals("opening the scroll...", progressMessage("complete"))
        assertEquals("server fallback", progressMessage("unknown_stage", "server fallback"))
        assertEquals("anky is working...", progressMessage("unknown_stage"))
        // Credit and x402 stages are gone from the subscription era —
        // unrecognized stages fall back to the generic line.
        listOf("credit_checked", "credit_spent", "credit_not_spent", "x402_quote_created", "x402_verified", "x402_settled").forEach { stage ->
            assertEquals("anky is working...", progressMessage(stage))
        }
    }

    @Test
    fun entitlementDenialMapsBothServerCodesToTheVeil() {
        assertTrue(isEntitlementDenied(MirrorClientError.Server(MirrorErrorCode.InsufficientCredits, "You need one credit.")))
        assertTrue(isEntitlementDenied(MirrorClientError.Server(MirrorErrorCode.TrialAlreadyClaimed, "Trial already claimed.")))
        assertTrue(isEntitlementDenied(MirrorClientError.Server(MirrorErrorCode.Unknown, "ENTITLEMENT_REQUIRED")))
        assertTrue(isEntitlementDenied(MirrorClientError.Server(MirrorErrorCode.Unknown, "Reflections open with the subscription.")))
        assertFalse(isEntitlementDenied(MirrorClientError.Server(MirrorErrorCode.RateLimited, "Rate limited.")))
        assertFalse(isEntitlementDenied(IllegalStateException("ENTITLEMENT_REQUIRED")))
    }

    @Test
    fun unentitledCompleteSessionIsVeiledAndNeverAsksMirror() = runTest {
        val stores = stores()
        val artifact = stores.archive.save(completeAnky())
        var mirrorClientBuildCount = 0

        val viewModel = viewModel(
            stores = stores,
            hash = artifact.hash,
            entitled = { false },
            mirrorClientProvider = {
                mirrorClientBuildCount += 1
                error("Free sessions make zero mirror calls.")
            },
        )

        val state = viewModel.state.value
        assertTrue(state.reflectionVeiled)
        assertFalse(state.entitled)
        assertFalse(state.canAskAnky)
        assertFalse(state.canSubmitReflectionRequest)

        viewModel.askAnky()
        advanceUntilIdle()

        assertFalse(viewModel.state.value.isAsking)
        assertEquals(0, mirrorClientBuildCount)
        assertEquals(null, viewModel.state.value.error)
    }

    @Test
    fun midSessionPurchaseLiftsVeilOnRefreshEntitlement() = runTest {
        val stores = stores()
        val artifact = stores.archive.save(completeAnky())
        var entitled = false
        val viewModel = viewModel(
            stores = stores,
            hash = artifact.hash,
            entitled = { entitled },
            mirrorClientProvider = { error("No mirror call in this test.") },
        )

        assertTrue(viewModel.state.value.reflectionVeiled)

        entitled = true
        viewModel.refreshEntitlement()

        assertFalse(viewModel.state.value.reflectionVeiled)
        assertTrue(viewModel.state.value.canAskAnky)
        assertTrue(viewModel.state.value.canSubmitReflectionRequest)
    }

    @Test
    fun serverEntitlementDenialDropsBehindTheVeilWithoutErrorCopy() = runTest {
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
            val viewModel = viewModel(
                stores = stores,
                hash = artifact.hash,
                entitled = { true },
                mirrorClientProvider = { MirrorClient(MirrorConfiguration(server.url("/").toString())) },
            )

            viewModel.askAnky()
            advanceUntilIdle()

            val state = viewModel.state.value
            assertFalse(state.entitled)
            assertTrue(state.reflectionVeiled)
            assertFalse(state.isAsking)
            assertFalse(state.canAskAnky)
            assertEquals(null, state.error)
            assertFalse(stores.requests.isPending(artifact.hash))
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun sealedSessionsAreImmutableAndOnlyFragmentsOfferContinueWriting() = runTest {
        val stores = stores()
        val sealed = stores.archive.save(completeAnky())
        val fragment = stores.archive.save(fragmentAnky())

        val sealedModel = viewModel(stores, sealed.hash, entitled = { true }) { error("no mirror") }
        val fragmentModel = viewModel(stores, fragment.hash, entitled = { true }) { error("no mirror") }

        assertTrue(sealedModel.state.value.artifact?.isComplete == true)
        assertFalse(sealedModel.state.value.canContinueWriting)
        assertTrue(fragmentModel.state.value.artifact?.isComplete == false)
        assertTrue(fragmentModel.state.value.canContinueWriting)
        // Fragments never reach the mirror, entitled or not.
        assertFalse(fragmentModel.state.value.canAskAnky)
        assertTrue(fragmentModel.state.value.remainingWritingTime.matches(Regex("""\d{2}:\d{2}""")))
    }

    @Test
    fun askAnkyDoesNotUploadWhenReflectionAlreadyExists() = runTest {
        val stores = stores()
        val artifact = stores.archive.save(completeAnky())
        stores.reflections.save(existingReflection(artifact.hash))
        var mirrorClientBuildCount = 0

        val viewModel = viewModel(
            stores = stores,
            hash = artifact.hash,
            entitled = { true },
            mirrorClientProvider = {
                mirrorClientBuildCount += 1
                error("Mirror client should not be created for an existing reflection.")
            },
        )

        viewModel.askAnky()
        advanceUntilIdle()

        assertFalse(viewModel.state.value.canAskAnky)
        assertFalse(viewModel.state.value.reflectionVeiled)
        assertFalse(viewModel.state.value.isAsking)
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
            val viewModel = viewModel(
                stores = stores,
                hash = artifact.hash,
                entitled = { true },
                mirrorClientProvider = { MirrorClient(MirrorConfiguration(server.url("/").toString())) },
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

        val viewModel = viewModel(
            stores = stores,
            hash = artifact.hash,
            entitled = { true },
            mirrorClientProvider = { error("raw transport detail") },
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
            val viewModel = viewModel(
                stores = stores,
                hash = artifact.hash,
                entitled = { true },
                mirrorClientProvider = { MirrorClient(MirrorConfiguration(server.url("/").toString())) },
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
    fun askAnkyStreamsProgressAndClearsStreamingBufferAfterSave() = runTest {
        val server = MockWebServer()
        val stores = stores()
        val artifact = stores.archive.save(completeAnky())
        stores.index.rebuild(stores.archive, stores.reflections)
        server.enqueue(streamingReflectionResponse(artifact.hash))
        server.start()
        try {
            val viewModel = viewModel(
                stores = stores,
                hash = artifact.hash,
                entitled = { true },
                mirrorClientProvider = { MirrorClient(MirrorConfiguration(server.url("/").toString())) },
            )

            viewModel.askAnky()
            advanceUntilIdle()

            assertFalse(viewModel.state.value.isAsking)
            assertEquals("", viewModel.state.value.streamingReflectionMarkdown)
            assertEquals(null, viewModel.state.value.progressStage)
            assertEquals("Small Thread", viewModel.state.value.reflection?.title)
            assertEquals(listOf("truth", "body"), viewModel.state.value.reflection?.tags)
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun copyTextIsSectionAwareAndReflectionIncludesTitleAndBody() = runTest {
        val stores = stores()
        val artifact = stores.archive.save(completeAnky())
        stores.reflections.save(existingReflection(artifact.hash, title = "Small Thread", body = "Here is what I saw."))
        val viewModel = viewModel(stores, artifact.hash, entitled = { true }) { error("Copy should not ask the mirror.") }

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
        stores.reflections.save(existingReflection(artifact.hash))
        stores.index.rebuild(stores.archive, stores.reflections)
        val viewModel = viewModel(stores, artifact.hash, entitled = { true }) { error("Delete should not create a mirror client.") }

        viewModel.deleteSession()
        advanceUntilIdle()

        assertTrue(viewModel.state.value.isDeleted)
        assertEquals(null, stores.reflections.load(artifact.hash))
        assertTrue(stores.index.load().isEmpty())
        assertFalse(artifact.file.exists())
    }

    @Test
    fun firstReflectionRequestsInAppReviewExactlyOnce() = runTest {
        val stores = stores()
        val artifact = stores.archive.save(completeAnky())
        stores.reflections.save(existingReflection(artifact.hash))
        var persisted = false
        val viewModel = RevealViewModel(
            hash = artifact.hash,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            requestStore = stores.requests,
            indexStore = stores.index,
            identityProvider = { identity() },
            mirrorClientProvider = { error("Review flow makes no mirror call.") },
            entitledForGatingProvider = { true },
            didRequestFirstReflectionReviewProvider = { persisted },
            persistFirstReflectionReviewRequested = { persisted = true },
            dispatcher = StandardTestDispatcher(testScheduler),
        )

        assertTrue(viewModel.state.value.shouldRequestReviewAfterReadingFirstReflection)

        viewModel.markFirstReflectionReviewRequested()
        assertTrue(persisted)
        assertFalse(viewModel.state.value.shouldRequestReviewAfterReadingFirstReflection)

        viewModel.load()
        assertFalse(viewModel.state.value.shouldRequestReviewAfterReadingFirstReflection)
    }

    @Test
    fun secondReflectionNeverPromptsForReview() = runTest {
        val stores = stores()
        val first = stores.archive.save(completeAnky())
        val second = stores.archive.save(fragmentAnky())
        stores.reflections.save(existingReflection(first.hash))
        stores.reflections.save(existingReflection(second.hash, title = "Second"))

        val viewModel = viewModel(stores, first.hash, entitled = { true }) { error("no mirror") }

        assertFalse(viewModel.state.value.shouldRequestReviewAfterReadingFirstReflection)
    }

    private fun kotlinx.coroutines.test.TestScope.viewModel(
        stores: Stores,
        hash: String,
        entitled: () -> Boolean,
        mirrorClientProvider: () -> MirrorClient,
    ): RevealViewModel =
        RevealViewModel(
            hash = hash,
            archive = stores.archive,
            reflectionStore = stores.reflections,
            requestStore = stores.requests,
            indexStore = stores.index,
            identityProvider = { identity() },
            mirrorClientProvider = mirrorClientProvider,
            entitledForGatingProvider = entitled,
            dispatcher = StandardTestDispatcher(testScheduler),
        )

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

    // No terminal-silence line: an unsealed fragment, well short of the
    // eight-minute ritual.
    private fun fragmentAnky(): String =
        "1770000000001 h\n1000 i"

    private fun existingReflection(
        hash: String,
        title: String = "Existing Thread",
        body: String = "Already reflected.",
    ): LocalReflection =
        LocalReflection(
            hash = hash,
            title = title,
            reflection = body,
            createdAt = Instant.EPOCH,
            creditsRemaining = null,
        )

    private fun identity(): WriterIdentity =
        WriterIdentity.fromRecoveryPhrase(
            inc.anky.android.core.identity.RecoveryPhrase.parse(
                "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
            ),
        )

    private fun reflectionResponse(hash: String): MockResponse =
        MockResponse()
            .setResponseCode(200)
            .setHeader("Content-Type", "text/markdown; charset=utf-8")
            .setHeader("X-Anky-Hash", hash)
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
                data: {"markdown":"# Small Thread\n\nHere is what I saw.","tags":["truth","body"],"headers":{"X-Anky-Hash":"$hash"}}

                """.trimIndent(),
            )

    private data class Stores(
        val archive: LocalAnkyArchive,
        val reflections: ReflectionStore,
        val requests: ReflectionRequestStore,
        val index: SessionIndexStore,
    )
}
