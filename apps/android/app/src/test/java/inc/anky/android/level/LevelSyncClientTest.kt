package inc.anky.android.level

import inc.anky.android.core.identity.RecoveryPhrase
import inc.anky.android.core.identity.WriterIdentity
import inc.anky.android.core.level.LevelPaintingPhase
import inc.anky.android.core.level.LevelProgressStore
import inc.anky.android.core.level.LevelSyncClient
import inc.anky.android.core.level.LevelSyncError
import inc.anky.android.core.level.LevelUnreportedSession
import java.io.File
import java.util.UUID
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

class LevelSyncClientTest {
    private lateinit var server: MockWebServer
    private lateinit var client: LevelSyncClient
    private val identity: WriterIdentity = WriterIdentity.fromRecoveryPhrase(
        RecoveryPhrase.parse(
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
        ),
    )

    private val statusJson = """
        {"status": {
            "totalSeconds": 700, "level": 2, "secondsIntoLevel": 220, "secondsRequired": 778,
            "percent": 0.28, "nextLevel": 3, "nextPaintingPhase": "generated",
            "nextPaintingTitle": "The Threshold", "nextPalette": ["#101010", "#a0a0a0"],
            "pendingCeremonyLevel": null
        }}
    """.trimIndent()

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        client = LevelSyncClient(baseUrl = server.url("/").toString())
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun reportSessionsPostsSignedBatchAndParsesStatus() = runTest {
        server.enqueue(MockResponse().setBody(statusJson))
        val status = client.reportSessions(
            listOf(LevelUnreportedSession(hash = "a".repeat(64), seconds = 480, sealedAtMs = 1_000)),
            identity,
        )
        assertEquals(700L, status.totalSeconds)
        assertEquals(2, status.level)
        assertEquals(LevelPaintingPhase.Generated, status.nextPaintingPhase)
        assertEquals("The Threshold", status.nextPaintingTitle)
        assertEquals(listOf("#101010", "#a0a0a0"), status.nextPalette)
        assertNull(status.pendingCeremonyLevel)

        val recorded = server.takeRequest()
        assertEquals("POST", recorded.method)
        assertEquals("/level/sessions", recorded.path)
        assertEquals(identity.accountId, recorded.getHeader("X-Anky-Account"))
        assertEquals("eip712", recorded.getHeader("X-Anky-Signature-Type"))
        assertNotNull(recorded.getHeader("X-Anky-Signature"))
        assertNotNull(recorded.getHeader("X-Anky-Request-Time"))
        val body = JSONObject(recorded.body.readUtf8())
        val sessions = body.getJSONArray("sessions")
        assertEquals(1, sessions.length())
        assertEquals("a".repeat(64), sessions.getJSONObject(0).getString("hash"))
        assertEquals(480L, sessions.getJSONObject(0).getLong("seconds"))
        assertEquals(1_000L, sessions.getJSONObject(0).getLong("sealedAtMs"))
    }

    @Test
    fun fetchStatusUsesSignedGet() = runTest {
        server.enqueue(MockResponse().setBody(statusJson))
        val status = client.fetchStatus(identity)
        assertEquals(3, status.nextLevel)

        val recorded = server.takeRequest()
        assertEquals("GET", recorded.method)
        assertEquals("/level/status", recorded.path)
        assertNotNull(recorded.getHeader("X-Anky-Signature"))
    }

    @Test
    fun prepareReturnsServerPhaseOrDefault() = runTest {
        server.enqueue(MockResponse().setBody("""{"phase": "generated"}"""))
        assertEquals("generated", client.prepare(level = 2, text = "chapter", identity = identity))
        var recorded = server.takeRequest()
        assertEquals("/level/prepare", recorded.path)
        val body = JSONObject(recorded.body.readUtf8())
        assertEquals(2, body.getInt("level"))
        assertEquals("chapter", body.getString("text"))

        server.enqueue(MockResponse().setBody("{}"))
        assertEquals("generationPending", client.prepare(level = 2, text = "chapter", identity = identity))
        server.takeRequest()
    }

    @Test
    fun ceremonyShownAndFunnelAndEmergencyPostExpectedPaths() = runTest {
        server.enqueue(MockResponse().setBody("{}"))
        client.reportCeremonyShown(level = 2, identity = identity)
        var recorded = server.takeRequest()
        assertEquals("/level/ceremony-shown", recorded.path)
        assertEquals(2, JSONObject(recorded.body.readUtf8()).getInt("level"))

        server.enqueue(MockResponse().setBody("{}"))
        client.reportFunnelEvent("boundary_reached", origin = "painting", identity = identity)
        recorded = server.takeRequest()
        assertEquals("/events/funnel", recorded.path)
        val funnelBody = JSONObject(recorded.body.readUtf8())
        assertEquals("boundary_reached", funnelBody.getString("event"))
        assertEquals("painting", funnelBody.getString("origin"))

        server.enqueue(MockResponse().setBody("{}"))
        client.reportEmergencyUnlock(identity)
        recorded = server.takeRequest()
        assertEquals("/events/emergency-unlock", recorded.path)
        assertEquals("{}", recorded.body.readUtf8())
    }

    @Test
    fun fetchAssetReturnsBinaryBody() = runTest {
        val bytes = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47)
        server.enqueue(MockResponse().setBody(okio.Buffer().write(bytes)))
        val data = client.fetchAsset(level = 2, file = "final.png", identity = identity)
        assertTrue(bytes.contentEquals(data))
        assertEquals("/level/assets/2/final.png", server.takeRequest().path)
    }

    @Test
    fun identifySubscriptionSendsWalletAndParsesState() = runTest {
        server.enqueue(
            MockResponse().setBody(
                """{"entitled": true, "productId": "anky.yearly", "expiresAtMs": 123, "store": "play_store", "periodType": "normal"}""",
            ),
        )
        val state = client.identifySubscription(identity)
        assertTrue(state.entitled)
        assertEquals("anky.yearly", state.productId)
        assertEquals(123L, state.expiresAtMs)
        assertEquals("play_store", state.store)
        assertEquals("normal", state.periodType)

        val recorded = server.takeRequest()
        assertEquals("/subscription/identify", recorded.path)
        assertEquals(identity.address, JSONObject(recorded.body.readUtf8()).getString("appUserId"))
    }

    @Test
    fun serverErrorsSurfaceAsTypedFailures() = runTest {
        server.enqueue(MockResponse().setResponseCode(503).setBody("down"))
        try {
            client.fetchStatus(identity)
            fail("expected LevelSyncError.Server")
        } catch (error: LevelSyncError.Server) {
            assertEquals(503, error.statusCode)
        }

        server.enqueue(MockResponse().setBody("not-json"))
        try {
            client.fetchStatus(identity)
            fail("expected LevelSyncError.InvalidResponse")
        } catch (error: LevelSyncError) {
            assertEquals(LevelSyncError.InvalidResponse, error)
        }
    }

    @Test
    fun flushUnreportedDrainsQueueAndAdoptsServerTotal() = runTest {
        val store = LevelProgressStore(
            File(
                File(System.getProperty("java.io.tmpdir"), "anky-flush-${UUID.randomUUID()}"),
                "level-progress.json",
            ),
        )
        store.creditSealedSession(hash = "b".repeat(64), durationMs = 100_000)
        server.enqueue(MockResponse().setBody(statusJson))

        LevelSyncClient.flushUnreported(store = store, identity = identity, client = client)

        assertTrue(store.unreportedSessions().isEmpty())
        assertEquals(700L, store.progress.totalSeconds)
    }

    @Test
    fun flushUnreportedKeepsQueueOnFailure() = runTest {
        val store = LevelProgressStore(
            File(
                File(System.getProperty("java.io.tmpdir"), "anky-flush-${UUID.randomUUID()}"),
                "level-progress.json",
            ),
        )
        store.creditSealedSession(hash = "c".repeat(64), durationMs = 100_000)
        server.enqueue(MockResponse().setResponseCode(500))

        LevelSyncClient.flushUnreported(store = store, identity = identity, client = client)

        assertEquals(1, store.unreportedSessions().size)
        assertEquals(100L, store.progress.totalSeconds)
    }
}
