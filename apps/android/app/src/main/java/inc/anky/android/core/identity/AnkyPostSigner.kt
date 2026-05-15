package inc.anky.android.core.identity

import inc.anky.android.core.protocol.AnkyHasher

data class SignedAnkyPost(
    val publicKey: String,
    val signature: String,
    val requestTime: String,
    val bodySha256: String,
)

object AnkyPostSigner {
    fun canonicalMessage(requestTime: String, bodySha256: String): String =
        listOf(
            "ANKY_POST_V1",
            "method:POST",
            "path:/anky",
            "request_time:$requestTime",
            "body_sha256:$bodySha256",
        ).joinToString(separator = "\n")

    fun sign(
        body: ByteArray,
        identity: WriterIdentity,
        requestTime: String = System.currentTimeMillis().toString(),
    ): SignedAnkyPost {
        val bodySha256 = AnkyHasher.sha256Hex(body)
        val message = canonicalMessage(requestTime = requestTime, bodySha256 = bodySha256)
        return SignedAnkyPost(
            publicKey = identity.publicKey,
            signature = identity.sign(message),
            requestTime = requestTime,
            bodySha256 = bodySha256,
        )
    }
}
