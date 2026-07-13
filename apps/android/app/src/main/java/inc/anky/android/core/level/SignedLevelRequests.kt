package inc.anky.android.core.level

import inc.anky.android.core.identity.AnkyPostSigner
import inc.anky.android.core.identity.WriterIdentity
import okhttp3.Request

/**
 * Wraps the existing EIP-712 [AnkyPostSigner] (owned by core/identity) for the
 * `level`, `events`, and `subscription` endpoints.
 *
 * Parity note: like iOS, the typed data always carries `method: "POST"` and
 * `path: "/anky"` regardless of the actual route — the server verifies the
 * same fixed message for every signed endpoint. Only the body hash, request
 * time, and account vary per request.
 */
internal object SignedLevelRequests {
    fun sign(builder: Request.Builder, body: ByteArray, identity: WriterIdentity): Request.Builder {
        val signed = AnkyPostSigner.sign(body = body, identity = identity)
        return builder
            .header("X-Anky-Identity-Version", signed.identityVersion)
            .header("X-Anky-Account", signed.accountId)
            .header("X-Anky-Signature-Type", signed.signatureType)
            .header("X-Anky-Signature", signed.signature)
            .header("X-Anky-Request-Time", signed.requestTime)
            .header("X-Anky-Client", signed.client)
    }
}
