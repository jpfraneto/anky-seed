package inc.anky.android.core.mirror

import inc.anky.android.core.identity.AnkyPostSigner
import inc.anky.android.core.identity.WriterIdentity
import inc.anky.android.core.protocol.AnkyHasher
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject

class MirrorClient(
    private val configuration: MirrorConfiguration,
    private val client: OkHttpClient = OkHttpClient(),
) {
    fun askAnky(bytes: ByteArray, identity: WriterIdentity): MirrorResponsePayload {
        val signed = AnkyPostSigner.sign(body = bytes, identity = identity)
        val base = configuration.baseUrl.trim().trimEnd('/')
        if (!base.startsWith("http://") && !base.startsWith("https://")) {
            throw MirrorClientError.InvalidUrl
        }
        val request = Request.Builder()
            .url("$base/anky")
            .post(bytes.toRequestBody("text/plain; charset=utf-8".toMediaType()))
            .header("Content-Type", "text/plain; charset=utf-8")
            .header("Accept", "application/json")
            .header("X-Anky-Public-Key", signed.publicKey)
            .header("X-Anky-Signature", signed.signature)
            .header("X-Anky-Request-Time", signed.requestTime)
            .header("X-Anky-Client", "android")
            .build()

        client.newCall(request).execute().use { response ->
            val bodyText = response.body?.string() ?: throw MirrorClientError.InvalidResponse
            val json = runCatching { JSONObject(bodyText) }.getOrElse {
                throw MirrorClientError.InvalidResponse
            }
            if (response.isSuccessful) {
                val payload = json.toMirrorResponsePayload()
                if (payload.hash != AnkyHasher.sha256Hex(bytes)) throw MirrorClientError.HashMismatch
                return payload
            }
            throw json.toMirrorServerError()
        }
    }
}

private fun JSONObject.toMirrorResponsePayload(): MirrorResponsePayload =
    MirrorResponsePayload(
        hash = getString("hash"),
        title = getString("title"),
        reflection = getString("reflection"),
        creditsRemaining = if (isNull("creditsRemaining")) null else getInt("creditsRemaining"),
    )

private fun JSONObject.toMirrorServerError(): MirrorClientError.Server {
    val error = optJSONObject("error")
    val code = error?.optString("code").toMirrorErrorCode()
    val message = error?.optString("message") ?: "Anky could not return a reflection right now."
    return MirrorClientError.Server(code, message)
}

private fun String?.toMirrorErrorCode(): MirrorErrorCode =
    when (this) {
        "INVALID_ANKY" -> MirrorErrorCode.InvalidAnky
        "INCOMPLETE_RITUAL" -> MirrorErrorCode.IncompleteRitual
        "MISSING_SIGNATURE" -> MirrorErrorCode.MissingSignature
        "INVALID_SIGNATURE" -> MirrorErrorCode.InvalidSignature
        "INSUFFICIENT_CREDITS" -> MirrorErrorCode.InsufficientCredits
        "DUPLICATE_IN_PROGRESS" -> MirrorErrorCode.DuplicateInProgress
        "RATE_LIMITED" -> MirrorErrorCode.RateLimited
        "MIRROR_FAILED" -> MirrorErrorCode.MirrorFailed
        "BODY_TOO_LARGE" -> MirrorErrorCode.BodyTooLarge
        else -> MirrorErrorCode.Unknown
    }
