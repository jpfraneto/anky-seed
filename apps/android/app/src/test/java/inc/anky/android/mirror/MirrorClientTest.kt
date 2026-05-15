package inc.anky.android.mirror

import inc.anky.android.core.identity.RecoveryPhrase
import inc.anky.android.core.identity.WriterIdentity
import inc.anky.android.core.mirror.MirrorClient
import inc.anky.android.core.mirror.MirrorClientError
import inc.anky.android.core.mirror.MirrorConfiguration
import inc.anky.android.core.mirror.MirrorEligibility
import inc.anky.android.core.mirror.MirrorErrorCode
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
        assertTrue(MirrorEligibility.canAsk("1770000000000 h\n100000 e\n100000 l\n100000 l\n100000 o\n72000 !\n8000"))
    }

    @Test
    fun sendsExactBodyBytesAndRequiredHeaders() {
        val server = MockWebServer()
        val body = "1770000000000 h\n100000 e\n100000 l\n100000 l\n100000 o\n72000 !\n8000"
            .toByteArray(Charsets.UTF_8)
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("""{"hash":"${AnkyHasher.sha256Hex(body)}","title":"Small Steady Thread","reflection":"Here is what I saw.","creditsRemaining":7}"""),
        )
        server.start()
        try {
            val client = MirrorClient(MirrorConfiguration(server.url("/").toString()))
            val response = client.askAnky(body, identity)
            val request = server.takeRequest()

            assertEquals("Small Steady Thread", response.title)
            assertArrayEquals(body, request.body.readByteArray())
            assertEquals("POST", request.method)
            assertEquals("/anky", request.path)
            assertEquals("text/plain; charset=utf-8", request.getHeader("Content-Type"))
            assertEquals("application/json", request.getHeader("Accept"))
            assertEquals(identity.publicKey, request.getHeader("X-Anky-Public-Key"))
            assertEquals("android", request.getHeader("X-Anky-Client"))
            assertTrue(request.getHeader("X-Anky-Signature")!!.isNotBlank())
            assertTrue(request.getHeader("X-Anky-Request-Time")!!.isNotBlank())
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
    fun parsesContractErrorCodesWithoutEchoingWriting() {
        val cases = listOf(
            400 to ("INCOMPLETE_RITUAL" to MirrorErrorCode.IncompleteRitual),
            401 to ("INVALID_SIGNATURE" to MirrorErrorCode.InvalidSignature),
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
