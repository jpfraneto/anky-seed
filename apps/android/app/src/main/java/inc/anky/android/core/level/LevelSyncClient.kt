package inc.anky.android.core.level

import inc.anky.android.core.identity.WriterIdentity
import java.io.IOException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.json.JSONArray
import org.json.JSONObject

/** Status mirror of the server's level ledger (`GET /level/status`). */
data class LevelServerStatus(
    val totalSeconds: Long,
    val level: Int,
    val secondsIntoLevel: Long,
    val secondsRequired: Long,
    val percent: Double,
    val nextLevel: Int,
    val nextPaintingPhase: LevelPaintingPhase,
    val nextPaintingTitle: String?,
    val nextPalette: List<String>?,
    val pendingCeremonyLevel: Int?,
)

/**
 * The server's answer after an identify: its webhook-maintained entitlement
 * for this wallet. `expiresAtMs` null is a valid entitled state (open-ended
 * promotional or lifetime grants).
 */
data class SubscriptionServerState(
    val entitled: Boolean,
    val productId: String?,
    val expiresAtMs: Long?,
    val store: String?,
    val periodType: String?,
)

sealed class LevelSyncError(message: String) : IOException(message) {
    object InvalidResponse : LevelSyncError("INVALID_RESPONSE") {
        private fun readResolve(): Any = InvalidResponse
    }

    data class Server(val statusCode: Int) : LevelSyncError("SERVER_$statusCode")
}

/** The network surface the painting machinery depends on (fakeable in tests). */
interface LevelSyncing {
    suspend fun reportSessions(sessions: List<LevelUnreportedSession>, identity: WriterIdentity): LevelServerStatus
    suspend fun fetchStatus(identity: WriterIdentity): LevelServerStatus
    suspend fun prepare(level: Int, text: String, identity: WriterIdentity): String
    suspend fun reportCeremonyShown(level: Int, identity: WriterIdentity)
    suspend fun fetchAsset(level: Int, file: String, identity: WriterIdentity): ByteArray
    suspend fun reportEmergencyUnlock(identity: WriterIdentity)
    suspend fun identifySubscription(identity: WriterIdentity): SubscriptionServerState
    suspend fun reportFunnelEvent(event: String, origin: String? = null, identity: WriterIdentity)
}

/**
 * Reports sealed sessions (hash + seconds only, never writing) to the server
 * ledger and reads level status back. Same signing plumbing as MirrorClient.
 */
class LevelSyncClient(
    baseUrl: String,
    private val client: OkHttpClient = OkHttpClient(),
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
) : LevelSyncing {
    private val base = baseUrl.trimEnd('/')

    override suspend fun reportSessions(
        sessions: List<LevelUnreportedSession>,
        identity: WriterIdentity,
    ): LevelServerStatus {
        val body = JSONObject()
            .put(
                "sessions",
                JSONArray().also { array ->
                    sessions.forEach { session ->
                        array.put(
                            JSONObject()
                                .put("hash", session.hash)
                                .put("seconds", session.seconds)
                                .put("sealedAtMs", session.sealedAtMs),
                        )
                    }
                },
            )
            .toString()
            .toByteArray(Charsets.UTF_8)
        val data = post("level/sessions", body, identity)
        return data.toJsonObject()?.optJSONObject("status")?.toLevelServerStatus()
            ?: throw LevelSyncError.InvalidResponse
    }

    override suspend fun fetchStatus(identity: WriterIdentity): LevelServerStatus {
        val data = get("level/status", identity)
        return data.toJsonObject()?.optJSONObject("status")?.toLevelServerStatus()
            ?: throw LevelSyncError.InvalidResponse
    }

    /**
     * Asks the server to distill + paint the package for `level`. The text
     * is the writing since the last level-up — transient on the server,
     * distilled once, forgotten. Returns the server's phase for the level.
     */
    override suspend fun prepare(level: Int, text: String, identity: WriterIdentity): String {
        val body = JSONObject()
            .put("level", level)
            .put("text", text)
            .toString()
            .toByteArray(Charsets.UTF_8)
        val data = post("level/prepare", body, identity)
        val phase = data.toJsonObject()?.optString("phase")?.takeIf { it.isNotBlank() }
        return phase ?: "generationPending"
    }

    /** Tells the ledger the unveiling was witnessed. Idempotent server-side. */
    override suspend fun reportCeremonyShown(level: Int, identity: WriterIdentity) {
        val body = JSONObject().put("level", level).toString().toByteArray(Charsets.UTF_8)
        post("level/ceremony-shown", body, identity)
    }

    /** Fetches one file of a level's painting package (signed empty body). */
    override suspend fun fetchAsset(level: Int, file: String, identity: WriterIdentity): ByteArray =
        get("level/assets/$level/$file", identity)

    /**
     * Analytics only (phase-2 §2): the emergency breath completed. One
     * signed event, nothing stored server-side, never surfaced to anyone.
     */
    override suspend fun reportEmergencyUnlock(identity: WriterIdentity) {
        post("events/emergency-unlock", "{}".toByteArray(Charsets.UTF_8), identity)
    }

    /**
     * Tells the mirror that this wallet is the RevenueCat appUserID. The
     * EIP-712 headers prove the wallet; RevenueCat webhooks carry the
     * entitlement truth server-side. The server rejects any attempt to
     * attach a different appUserID to the authenticated account.
     */
    override suspend fun identifySubscription(identity: WriterIdentity): SubscriptionServerState {
        val body = JSONObject().put("appUserId", identity.address).toString().toByteArray(Charsets.UTF_8)
        val data = post("subscription/identify", body, identity)
        val json = data.toJsonObject() ?: throw LevelSyncError.InvalidResponse
        if (!json.has("entitled")) throw LevelSyncError.InvalidResponse
        return SubscriptionServerState(
            entitled = json.getBoolean("entitled"),
            productId = json.optStringOrNull("productId"),
            expiresAtMs = if (json.has("expiresAtMs") && !json.isNull("expiresAtMs")) json.getLong("expiresAtMs") else null,
            store = json.optStringOrNull("store"),
            periodType = json.optStringOrNull("periodType"),
        )
    }

    /**
     * One signed funnel event (phase-3 §6). Whitelisted names server-side;
     * hashed account, event, origin — never anything about writing.
     */
    override suspend fun reportFunnelEvent(event: String, origin: String?, identity: WriterIdentity) {
        val body = JSONObject()
            .put("event", event)
            .apply { origin?.let { put("origin", it) } }
            .toString()
            .toByteArray(Charsets.UTF_8)
        post("events/funnel", body, identity)
    }

    private suspend fun post(path: String, body: ByteArray, identity: WriterIdentity): ByteArray =
        execute(
            SignedLevelRequests.sign(Request.Builder(), body, identity)
                .url(url(path))
                .post(body.toRequestBody("application/json".toMediaType()))
                .header("Content-Type", "application/json"),
        )

    private suspend fun get(path: String, identity: WriterIdentity): ByteArray =
        execute(
            SignedLevelRequests.sign(Request.Builder(), ByteArray(0), identity)
                .url(url(path))
                .get(),
        )

    private fun url(path: String): okhttp3.HttpUrl =
        "$base/$path".toHttpUrlOrNull() ?: throw LevelSyncError.InvalidResponse

    private suspend fun execute(builder: Request.Builder): ByteArray =
        withContext(ioDispatcher) {
            client.newCall(builder.build()).execute().use { response ->
                ensureSuccess(response)
                response.body?.bytes() ?: ByteArray(0)
            }
        }

    private fun ensureSuccess(response: Response) {
        if (response.code !in 200..299) {
            throw LevelSyncError.Server(statusCode = response.code)
        }
    }

    companion object {
        /**
         * Drains the unreported queue: posts a batch, marks acknowledged
         * hashes reported, and adopts the server total if it is ahead of
         * this install. Failures leave the queue intact for the next pass.
         */
        suspend fun flushUnreported(
            store: LevelProgressStore,
            identity: WriterIdentity?,
            client: LevelSyncing,
        ) {
            val pending = store.unreportedSessions()
            if (pending.isEmpty() || identity == null) return
            val status = runCatching { client.reportSessions(pending, identity) }.getOrNull() ?: return
            store.markReported(pending.map { it.hash })
            store.adoptServerTotalIfHigher(status.totalSeconds)
        }
    }
}

/**
 * Fire-and-forget funnel reporting (phase-3 §6). Analytics never block or
 * break the practice: failures are silently dropped, the app never waits.
 */
class AnkyFunnel(
    private val client: LevelSyncing,
    private val identityProvider: suspend () -> WriterIdentity?,
    private val scope: CoroutineScope,
) {
    fun report(event: String, origin: String? = null) {
        scope.launch {
            val identity = runCatching { identityProvider() }.getOrNull() ?: return@launch
            runCatching { client.reportFunnelEvent(event, origin, identity) }
        }
    }

    companion object {
        const val CeremonyOneShown = "ceremony_1_shown"
        const val BoundaryReached = "boundary_reached"
        const val VeilTapped = "veil_tapped"
        const val PaywallShown = "paywall_shown"
        const val TrialStarted = "trial_started"
        const val Subscribed = "subscribed"
        const val Restored = "restored"
        const val Lapsed = "lapsed"
    }
}

private fun ByteArray.toJsonObject(): JSONObject? =
    runCatching { JSONObject(toString(Charsets.UTF_8)) }.getOrNull()

private fun JSONObject.optStringOrNull(name: String): String? =
    if (has(name) && !isNull(name)) getString(name).takeIf { it.isNotEmpty() } else null

private fun JSONObject.toLevelServerStatus(): LevelServerStatus? {
    val phase = LevelPaintingPhase.fromRawValue(optString("nextPaintingPhase")) ?: return null
    if (!has("totalSeconds") || !has("level")) return null
    val paletteArray = optJSONArray("nextPalette")
    val palette = paletteArray?.let { array ->
        (0 until array.length()).map { array.getString(it) }
    }
    return LevelServerStatus(
        totalSeconds = getLong("totalSeconds"),
        level = getInt("level"),
        secondsIntoLevel = getLong("secondsIntoLevel"),
        secondsRequired = getLong("secondsRequired"),
        percent = getDouble("percent"),
        nextLevel = getInt("nextLevel"),
        nextPaintingPhase = phase,
        nextPaintingTitle = optStringOrNull("nextPaintingTitle"),
        nextPalette = palette,
        pendingCeremonyLevel = if (has("pendingCeremonyLevel") && !isNull("pendingCeremonyLevel")) {
            getInt("pendingCeremonyLevel")
        } else {
            null
        },
    )
}
