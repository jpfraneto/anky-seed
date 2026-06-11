package inc.anky.android.core.mirror

import inc.anky.android.core.identity.AnkyPostSigner
import inc.anky.android.core.identity.WriterIdentity
import inc.anky.android.core.protocol.AnkyHasher
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject

class MirrorClient(
    private val configuration: MirrorConfiguration,
    private val client: OkHttpClient = OkHttpClient(),
) {
    fun askAnky(
        bytes: ByteArray,
        identity: WriterIdentity,
        appVersion: String? = null,
        intent: MirrorIntent = MirrorIntent.Reflection,
        progress: ((MirrorProgressEvent) -> Unit)? = null,
        reflectionChunk: ((MirrorReflectionChunkEvent) -> Unit)? = null,
    ): MirrorResponsePayload {
        val signed = AnkyPostSigner.sign(body = bytes, identity = identity)
        val base = configuration.effectiveBaseUrl().trimEnd('/')
        if (!base.startsWith("http://") && !base.startsWith("https://")) {
            throw MirrorClientError.InvalidUrl
        }
        val url = "$base/anky".toHttpUrlOrNull() ?: throw MirrorClientError.InvalidUrl
        val request = Request.Builder()
            .url(url)
            .post(bytes.toRequestBody("text/plain; charset=utf-8".toMediaType()))
            .header("Content-Type", "text/plain; charset=utf-8")
            .header("Accept", "text/event-stream")
            .header("X-Anky-Identity-Version", signed.identityVersion)
            .header("X-Anky-Account", signed.accountId)
            .header("X-Anky-Signature-Type", signed.signatureType)
            .header("X-Anky-Signature", signed.signature)
            .header("X-Anky-Request-Time", signed.requestTime)
            .header("X-Anky-Client", signed.client)
            .header("X-Anky-Intent", intent.headerValue)
            .apply {
                if (!appVersion.isNullOrBlank()) {
                    header("X-Anky-App-Version", appVersion)
                }
            }
            .build()

        client.newCall(request).execute().use { response ->
            val body = response.body ?: throw MirrorClientError.InvalidResponse
            val bodyText = if (response.isSuccessful && response.isEventStream()) null else body.string()
            if (response.isSuccessful) {
                val payload = if (response.isEventStream()) {
                    parseEventStream(
                        source = body.source(),
                        bytes = bytes,
                        progress = progress,
                        reflectionChunk = reflectionChunk,
                    )
                } else {
                    val reflection = bodyText?.trim()?.takeIf { it.isNotEmpty() }
                        ?: throw MirrorClientError.InvalidResponse
                    MirrorResponsePayload(
                        hash = response.header("X-Anky-Hash") ?: AnkyHasher.sha256Hex(bytes),
                        title = titleFromMarkdown(reflection),
                        reflection = reflection,
                        tags = response.header("X-Anky-Tags").tags().orEmpty(),
                        creditsRemaining = response.header("X-Anky-Credits-Remaining").creditsRemaining(),
                    )
                }
                if (payload.hash != AnkyHasher.sha256Hex(bytes)) throw MirrorClientError.HashMismatch
                return payload
            }
            throw bodyText
                ?.toJsonObjectOrNull()
                ?.toMirrorServerError()
                ?: MirrorClientError.Server(
                    MirrorErrorCode.Unknown,
                    "Anky could not return a reflection right now.",
                )
        }
    }

    private fun parseEventStream(
        source: okio.BufferedSource,
        bytes: ByteArray,
        progress: ((MirrorProgressEvent) -> Unit)?,
        reflectionChunk: ((MirrorReflectionChunkEvent) -> Unit)?,
    ): MirrorResponsePayload {
        var currentEvent: String? = null
        val dataLines = mutableListOf<String>()

        fun flush(): MirrorResponsePayload? {
            val event = currentEvent ?: run {
                dataLines.clear()
                return null
            }
            val payload = dataLines.joinToString("\n")
            dataLines.clear()
            return when (event) {
                "update" -> {
                    payload.toJsonObjectOrNull()?.let { json ->
                        progress?.invoke(
                            MirrorProgressEvent(
                                stage = json.optString("stage"),
                                message = json.optString("message").takeIf { it.isNotBlank() },
                            ),
                        )
                    }
                    null
                }
                "reflection_chunk" -> {
                    payload.toJsonObjectOrNull()?.let { json ->
                        reflectionChunk?.invoke(
                            MirrorReflectionChunkEvent(
                                chunk = json.optString("chunk"),
                                generatedCharacters = json.optInt("generatedCharacters"),
                            ),
                        )
                    }
                    null
                }
                "reflection" -> reflectionPayloadFromEvent(payload, bytes)
                "error" -> throw MirrorClientError.Server(MirrorErrorCode.Unknown, errorMessageFromSsePayload(payload))
                else -> null
            }
        }

        while (true) {
            val line = source.readUtf8Line() ?: break
            val trimmedLine = line.trim()
            if (trimmedLine.isEmpty()) {
                flush()?.let { return it }
                currentEvent = null
                continue
            }
            when {
                trimmedLine.startsWith("event:") -> {
                    if (currentEvent != null) {
                        flush()?.let { return it }
                    }
                    currentEvent = trimmedLine.removePrefix("event:").trim()
                }
                trimmedLine.startsWith("data:") -> {
                    dataLines += trimmedLine.removePrefix("data:").trim()
                }
            }
        }

        flush()?.let { return it }
        throw MirrorClientError.InvalidResponse
    }
}

internal fun MirrorConfiguration.effectiveBaseUrl(): String {
    val candidate = baseUrl.trim()
    return candidate.ifEmpty { MirrorConfiguration().baseUrl }
}

private fun String.toJsonObjectOrNull(): JSONObject? =
    runCatching { JSONObject(this) }.getOrNull()

private fun JSONObject.toMirrorServerError(): MirrorClientError.Server {
    val error = optJSONObject("error")
    val code = error?.optString("code").toMirrorErrorCode()
    val message = error
        ?.optString("message")
        ?.takeUnless { it.isBlank() }
        ?: "Anky could not return a reflection right now."
    return MirrorClientError.Server(code, message)
}

private fun reflectionPayloadFromEvent(payload: String, bytes: ByteArray): MirrorResponsePayload {
    val json = payload.toJsonObjectOrNull() ?: throw MirrorClientError.InvalidResponse
    val reflection = json.optString("markdown").trim().takeIf { it.isNotEmpty() }
        ?: throw MirrorClientError.InvalidResponse
    val headers = json.optJSONObject("headers")
    val hash = headers.headerValue("X-Anky-Hash") ?: AnkyHasher.sha256Hex(bytes)
    val tags = json.optJSONArray("tags").stringList()
        .ifEmpty { headers.headerValue("X-Anky-Tags").tags().orEmpty() }
    return MirrorResponsePayload(
        hash = hash,
        title = titleFromMarkdown(reflection),
        reflection = reflection,
        tags = tags,
        creditsRemaining = headers.headerValue("X-Anky-Credits-Remaining").creditsRemaining(),
    )
}

private fun errorMessageFromSsePayload(payload: String): String {
    val json = payload.toJsonObjectOrNull() ?: return "Anky could not return a reflection right now."
    val body = json.optJSONObject("body")
    val error = body?.optJSONObject("error")
    return error?.optString("message")?.takeIf { it.isNotBlank() }
        ?: json.optString("message").takeIf { it.isNotBlank() }
        ?: "Anky could not return a reflection right now."
}

private fun String?.toMirrorErrorCode(): MirrorErrorCode =
    when (this) {
        "INVALID_ANKY" -> MirrorErrorCode.InvalidAnky
        "INCOMPLETE_RITUAL" -> MirrorErrorCode.IncompleteRitual
        "MISSING_IDENTITY_VERSION" -> MirrorErrorCode.MissingSignature
        "UNSUPPORTED_IDENTITY_VERSION" -> MirrorErrorCode.InvalidSignature
        "MISSING_ACCOUNT" -> MirrorErrorCode.MissingSignature
        "INVALID_ACCOUNT" -> MirrorErrorCode.InvalidSignature
        "UNSUPPORTED_CHAIN" -> MirrorErrorCode.InvalidSignature
        "INVALID_SIGNATURE_TYPE" -> MirrorErrorCode.InvalidSignature
        "MISSING_SIGNATURE" -> MirrorErrorCode.MissingSignature
        "INVALID_SIGNATURE" -> MirrorErrorCode.InvalidSignature
        "INSUFFICIENT_CREDITS" -> MirrorErrorCode.InsufficientCredits
        "TRIAL_ALREADY_CLAIMED" -> MirrorErrorCode.TrialAlreadyClaimed
        "DUPLICATE_IN_PROGRESS" -> MirrorErrorCode.DuplicateInProgress
        "RATE_LIMITED" -> MirrorErrorCode.RateLimited
        "MIRROR_FAILED" -> MirrorErrorCode.MirrorFailed
        "BODY_TOO_LARGE" -> MirrorErrorCode.BodyTooLarge
        else -> MirrorErrorCode.Unknown
    }

private fun String?.creditsRemaining(): Int? =
    if (this == null || this == "null") null else toIntOrNull()

private fun String?.tags(): List<String>? {
    if (this.isNullOrBlank()) return null
    return runCatching { JSONArray(this).stringList() }.getOrNull()
}

private fun JSONArray?.stringList(): List<String> {
    if (this == null) return emptyList()
    return (0 until length()).mapNotNull { index ->
        optString(index).trim().takeIf { it.isNotEmpty() }
    }
}

private fun JSONObject?.headerValue(name: String): String? {
    if (this == null) return null
    val keys = keys()
    while (keys.hasNext()) {
        val key = keys.next()
        if (key.equals(name, ignoreCase = true)) return optString(key).takeIf { it.isNotBlank() }
    }
    return null
}

private fun okhttp3.Response.isEventStream(): Boolean =
    header("Content-Type")?.contains("text/event-stream", ignoreCase = true) == true

private fun titleFromMarkdown(markdown: String): String {
    val lines = markdown.lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.toList()
    val heading = lines.firstOrNull { it.startsWith("# ") }?.removePrefix("# ")?.trim()
    val fallback = lines.firstOrNull()
    return heading?.takeIf { it.isNotEmpty() }
        ?: fallback?.takeIf { it.isNotEmpty() }
        ?: "reflection"
}
