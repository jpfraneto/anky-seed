package inc.anky.android.feature.reveal

import inc.anky.android.core.identity.WriterIdentity
import inc.anky.android.core.mirror.MirrorClient
import inc.anky.android.core.mirror.MirrorConfiguration
import inc.anky.android.core.mirror.ReflectionCreditPromptState
import inc.anky.android.core.storage.LocalAnkyArchive
import inc.anky.android.core.storage.LocalReflection
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
    fun askAnkyStoresCreditsRemainingWithoutInvalidatingCreditCache() = runTest {
        val server = MockWebServer()
        val stores = stores()
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
                dispatcher = StandardTestDispatcher(testScheduler),
            )

            viewModel.askAnky()
            advanceUntilIdle()

            assertEquals(7, stores.reflections.load(artifact.hash)?.creditsRemaining)
            assertEquals(7, viewModel.state.value.creditBalance)
            assertTrue(viewModel.state.value.hasClaimedFreeCredits)
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun claimedFreeCreditsWithoutBalanceKeepsPromptUnknownAndAllowsBackendCheck() = runTest {
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

        assertEquals(ReflectionCreditPromptState.Unknown, viewModel.state.value.creditPromptState)
        assertEquals("Reflection balance updates after mirroring", viewModel.state.value.creditPromptMessage)
        assertTrue(viewModel.state.value.canSubmitReflectionRequest)
        viewModel.askAnky()
        advanceUntilIdle()
        assertFalse(viewModel.state.value.isAsking)
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
            val viewModel = RevealViewModel(
                hash = artifact.hash,
                archive = stores.archive,
                reflectionStore = stores.reflections,
                indexStore = stores.index,
                identityProvider = { identity() },
                mirrorClientProvider = { MirrorClient(MirrorConfiguration(server.url("/").toString())) },
                hasClaimedFreeCreditsProvider = { true },
                dispatcher = StandardTestDispatcher(testScheduler),
            )

            viewModel.askAnky()
            advanceUntilIdle()

            assertEquals(0, viewModel.state.value.creditBalance)
            assertTrue(viewModel.state.value.creditsDenied)
            assertEquals(ReflectionCreditPromptState.Unavailable, viewModel.state.value.creditPromptState)
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun askAnkyDoesNotInvalidateCreditCacheWhenCreditsRemainingIsNull() = runTest {
        val server = MockWebServer()
        val stores = stores()
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
                dispatcher = StandardTestDispatcher(testScheduler),
            )

            viewModel.askAnky()
            advanceUntilIdle()

            assertEquals(null, stores.reflections.load(artifact.hash)?.creditsRemaining)
        } finally {
            server.shutdown()
        }
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
            index = SessionIndexStore.forFile(File(root, "session-index.json")),
        )
    }

    private fun completeAnky(): String =
        "1770000000000 h\n100000 e\n100000 l\n100000 l\n100000 o\n72000 !\n8000"

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
            .setBody("# Small Thread\n\nHere is what I saw.")

    private data class Stores(
        val archive: LocalAnkyArchive,
        val reflections: ReflectionStore,
        val index: SessionIndexStore,
    )
}
