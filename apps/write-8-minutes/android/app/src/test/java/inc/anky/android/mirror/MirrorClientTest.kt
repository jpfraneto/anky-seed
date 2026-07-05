package inc.anky.android.mirror

import inc.anky.android.BuildConfig
import inc.anky.android.core.identity.RecoveryPhrase
import inc.anky.android.core.identity.WriterIdentity
import inc.anky.android.core.mirror.MirrorClient
import inc.anky.android.core.mirror.MirrorClientError
import inc.anky.android.core.mirror.MirrorConfiguration
import inc.anky.android.core.mirror.MirrorEligibility
import inc.anky.android.core.mirror.AnkyReflectionPrompt
import inc.anky.android.core.mirror.MirrorErrorCode
import inc.anky.android.core.mirror.MirrorIntent
import inc.anky.android.core.mirror.ReflectionCreditPresentation
import inc.anky.android.core.mirror.ReflectionCreditPromptState
import inc.anky.android.core.mirror.effectiveBaseUrl
import inc.anky.android.core.protocol.AnkyHasher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MirrorClientTest {
    private val identity = WriterIdentity.fromRecoveryPhrase(
        RecoveryPhrase.parse("able about above absent absorb abstract access accident account across action actual"),
    )

    @Test
    fun eligibilityRejectsFragments() {
        assertFalse(MirrorEligibility.canAsk("1770000000000 h\n0042 e"))
        assertTrue(MirrorEligibility.canAsk("1770000000000 h\n100000 e\n100000 l\n100000 l\n100000 o\n80000 !\n8000"))
        assertFalse(MirrorEligibility.canAsk(isComplete = false, hasReflection = false))
        assertTrue(MirrorEligibility.canAsk(isComplete = true, hasReflection = false))
        assertFalse(MirrorEligibility.canAsk(isComplete = true, hasReflection = true))
    }

    @Test
    fun firstFreeCreditStateShowsGiftUntilClaimed() {
        val state = ReflectionCreditPresentation.state(
            creditsRemaining = null,
            hasClaimedFreeCredits = false,
        )

        assertEquals(ReflectionCreditPromptState.FreeGift(2), state)
        assertEquals("2 reflections available on this device", ReflectionCreditPresentation.messageFor(state))
    }

    @Test
    fun reflectionPromptCopiesMasterPromptWithReconstructedWriting() {
        val prompt = AnkyReflectionPrompt.build("dear diary")

        assertTrue(prompt.startsWith("Take a look at this stream-of-consciousness journal entry."))
        assertTrue(prompt.contains("Reply with pure markdown"))
        assertTrue(prompt.contains("---\n\ndear diary"))
    }

    @Test
    fun creditPromptShowsBalanceAndUnavailableState() {
        val available = ReflectionCreditPresentation.state(
            creditsRemaining = 2,
            hasClaimedFreeCredits = true,
        )
        val unavailable = ReflectionCreditPresentation.state(
            creditsRemaining = 0,
            hasClaimedFreeCredits = true,
        )
        val unavailableBeforeClaim = ReflectionCreditPresentation.state(
            creditsRemaining = 0,
            hasClaimedFreeCredits = false,
        )

        assertEquals(ReflectionCreditPromptState.Available(2), available)
        assertEquals("You have 2 reflections left", ReflectionCreditPresentation.messageFor(available))
        assertEquals(ReflectionCreditPromptState.Unavailable, unavailable)
        assertEquals(ReflectionCreditPromptState.Unavailable, unavailableBeforeClaim)
        assertEquals("No reflections left", ReflectionCreditPresentation.messageFor(unavailable))
    }

    @Test
    fun claimedFreeCreditWithoutLoadedBalanceStartsUnavailableLikeIos() {
        val unavailable = ReflectionCreditPresentation.state(
            creditsRemaining = null,
            hasClaimedFreeCredits = true,
        )

        assertEquals(ReflectionCreditPromptState.Unavailable, unavailable)
        assertEquals("No reflections left", ReflectionCreditPresentation.messageFor(unavailable))
    }

    @Test
    fun blankMirrorUrlFallsBackToDefaultLikeIos() {
        assertEquals(
            BuildConfig.DEFAULT_MIRROR_BASE_URL,
            MirrorConfiguration(" \n\t ").effectiveBaseUrl(),
        )
    }

    @Test
    fun invalidMirrorUrlUsesIosCopy() {
        val body = "1770000000000 h\n100000 e\n100000 l\n100000 l\n100000 o\n80000 !\n8000"
            .toByteArray(Charsets.UTF_8)
        val invalidUrls = listOf("not a url", "http://")

        for (url in invalidUrls) {
            try {
                MirrorClient(MirrorConfiguration(url)).askAnky(body, identity)
                error("Expected invalid URL error")
            } catch (error: MirrorClientError.InvalidUrl) {
                assertEquals("The mirror URL is not valid.", error.message)
            }
        }
    }

    @Test
    fun sendsExactBodyBytesAndRequiredHeaders() {
        val server = MockWebServer()
        val body = "1770000000000 h\n100000 e\n100000 l\n100000 l\n100000 o\n80000 !\n8000"
            .toByteArray(Charsets.UTF_8)
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "text/markdown; charset=utf-8")
                .setHeader("X-Anky-Hash", AnkyHasher.sha256Hex(body))
                .setHeader("X-Anky-Credits-Remaining", "7")
                .setHeader("X-Anky-Tags", """["truth","body"]""")
                .setBody("# Small Steady Thread\n\nHere is what I saw."),
        )
        server.start()
        try {
            val client = MirrorClient(MirrorConfiguration(server.url("/").toString()))
            val response = client.askAnky(body, identity, appVersion = "1.0(1)")
            val request = server.takeRequest()

            assertEquals("Small Steady Thread", response.title)
            assertEquals(listOf("truth", "body"), response.tags)
            assertArrayEquals(body, request.body.readByteArray())
            assertEquals("POST", request.method)
            assertEquals("/anky", request.path)
            assertEquals("text/plain; charset=utf-8", request.getHeader("Content-Type"))
            assertEquals("text/event-stream", request.getHeader("Accept"))
            assertEquals("anky.base.eoa.v1", request.getHeader("X-Anky-Identity-Version"))
            assertEquals(identity.accountId, request.getHeader("X-Anky-Account"))
            assertEquals("eip712", request.getHeader("X-Anky-Signature-Type"))
            assertEquals(null, request.getHeader("X-Anky-Public-Key"))
            assertEquals("android", request.getHeader("X-Anky-Client"))
            assertEquals("reflection", request.getHeader("X-Anky-Intent"))
            assertEquals("1.0(1)", request.getHeader("X-Anky-App-Version"))
            assertEquals(null, request.getHeader("X-Anky-Trial-Proof"))
            val signature = request.getHeader("X-Anky-Signature")!!
            val requestTime = request.getHeader("X-Anky-Request-Time")!!
            assertTrue(signature.isNotBlank())
            assertTrue(signature.startsWith("0x"))
            assertEquals(132, signature.length)
            assertTrue(requestTime.isNotBlank())
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun parsesStreamingReflectionEventsAndChunks() {
        val server = MockWebServer()
        val body = "1770000000000 h\n100000 e\n100000 l\n100000 l\n100000 o\n80000 !\n8000"
            .toByteArray(Charsets.UTF_8)
        server.enqueue(
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
                    data: {"markdown":"# Small Thread\n\nHere is what I saw.","tags":["truth","body"],"headers":{"X-Anky-Hash":"${AnkyHasher.sha256Hex(body)}","X-Anky-Credits-Remaining":"5"}}

                    """.trimIndent(),
                ),
        )
        server.start()
        try {
            val events = mutableListOf<String>()
            val chunks = StringBuilder()
            val response = MirrorClient(MirrorConfiguration(server.url("/").toString())).askAnky(
                body,
                identity,
                progress = { events += it.stage },
                reflectionChunk = { chunks.append(it.chunk) },
            )

            assertEquals(listOf("provider_started"), events)
            assertEquals("# Small Thread", chunks.toString())
            assertEquals("Small Thread", response.title)
            assertEquals(listOf("truth", "body"), response.tags)
            assertEquals(5, response.creditsRemaining)
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun canRequestNudgeIntent() {
        val server = MockWebServer()
        val body = "1770000000000 h\n4000 i".toByteArray(Charsets.UTF_8)
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "text/plain; charset=utf-8")
                .setHeader("X-Anky-Hash", AnkyHasher.sha256Hex(body))
                .setHeader("X-Anky-Credits-Remaining", "6")
                .setBody("follow the warm sentence."),
        )
        server.start()
        try {
            val client = MirrorClient(MirrorConfiguration(server.url("/").toString()))
            val response = client.askAnky(body, identity, intent = MirrorIntent.Nudge)
            val request = server.takeRequest()

            assertEquals("nudge", request.getHeader("X-Anky-Intent"))
            assertArrayEquals(body, request.body.readByteArray())
            assertEquals("follow the warm sentence.", response.reflection)
            assertEquals(6, response.creditsRemaining)
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun parsesServerErrorCodes() {
        val server = MockWebServer()
        server.enqueue(
            MockResponse()
                .setResponseCode(402)
                .setBody("""{"error":{"code":"INSUFFICIENT_CREDITS","message":"You need one credit to ask Anky for a reflection."}}"""),
        )
        server.start()
        try {
            val client = MirrorClient(MirrorConfiguration(server.url("/").toString()))
            try {
                client.askAnky("1770000000000 h\n8000".toByteArray(Charsets.UTF_8), identity)
                error("Expected server error")
            } catch (error: MirrorClientError.Server) {
                assertEquals(MirrorErrorCode.InsufficientCredits, error.code)
            }
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun malformedServerErrorBodyUsesGenericServerCopyLikeIos() {
        val server = MockWebServer()
        server.enqueue(
            MockResponse()
                .setResponseCode(500)
                .setBody("not json"),
        )
        server.start()
        try {
            val client = MirrorClient(MirrorConfiguration(server.url("/").toString()))
            try {
                client.askAnky("1770000000000 h\n8000".toByteArray(Charsets.UTF_8), identity)
                error("Expected server error")
            } catch (error: MirrorClientError.Server) {
                assertEquals(MirrorErrorCode.Unknown, error.code)
                assertEquals("Anky could not return a reflection right now.", error.message)
            }
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun successfulEmptyMarkdownUsesInvalidResponseCopy() {
        val server = MockWebServer()
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("  \n"),
        )
        server.start()
        try {
            val client = MirrorClient(MirrorConfiguration(server.url("/").toString()))
            try {
                client.askAnky("1770000000000 h\n8000".toByteArray(Charsets.UTF_8), identity)
                error("Expected invalid response")
            } catch (error: MirrorClientError.InvalidResponse) {
                assertEquals("The mirror returned an invalid response.", error.message)
            }
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun parsesContractErrorCodesWithoutEchoingWriting() {
        val cases = listOf(
            400 to ("INCOMPLETE_RITUAL" to MirrorErrorCode.IncompleteRitual),
            401 to ("INVALID_SIGNATURE" to MirrorErrorCode.InvalidSignature),
            402 to ("TRIAL_ALREADY_CLAIMED" to MirrorErrorCode.TrialAlreadyClaimed),
            500 to ("MIRROR_FAILED" to MirrorErrorCode.MirrorFailed),
        )
        val body = "1770000000000 h\n8000".toByteArray(Charsets.UTF_8)

        for ((status, expected) in cases) {
            val server = MockWebServer()
            server.enqueue(
                MockResponse()
                    .setResponseCode(status)
                    .setBody("""{"error":{"code":"${expected.first}","message":"contract-safe error"}}"""),
            )
            server.start()
            try {
                val client = MirrorClient(MirrorConfiguration(server.url("/").toString()))
                try {
                    client.askAnky(body, identity)
                    error("Expected server error")
                } catch (error: MirrorClientError.Server) {
                    assertEquals(expected.second, error.code)
                    assertEquals("contract-safe error", error.message)
                }
            } finally {
                server.shutdown()
            }
        }
    }
}
