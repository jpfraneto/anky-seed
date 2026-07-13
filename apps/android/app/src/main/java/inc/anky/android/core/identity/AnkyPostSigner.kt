package inc.anky.android.core.identity

import inc.anky.android.core.protocol.AnkyHasher
import org.json.JSONArray
import org.json.JSONObject
import org.web3j.crypto.StructuredDataEncoder

data class SignedAnkyPost(
    val identityVersion: String,
    val accountId: String,
    val signatureType: String,
    val signature: String,
    val requestTime: String,
    val client: String,
    val bodySha256: String,
)

object AnkyPostSigner {
    fun sign(
        body: ByteArray,
        identity: WriterIdentity,
        requestTime: String = System.currentTimeMillis().toString(),
        client: String = "android",
    ): SignedAnkyPost {
        val bodySha256 = "0x${AnkyHasher.sha256Hex(body)}"
        val typedData = typedDataJson(
            identity = identity,
            bodySha256 = bodySha256,
            requestTime = requestTime,
            client = client,
        )
        val digest = StructuredDataEncoder(typedData.toString()).hashStructuredData()
        return SignedAnkyPost(
            identityVersion = WriterIdentity.IdentityVersion,
            accountId = identity.accountId,
            signatureType = "eip712",
            signature = identity.signDigest(digest),
            requestTime = requestTime,
            client = client,
            bodySha256 = bodySha256,
        )
    }

    fun typedDataJson(
        identity: WriterIdentity,
        bodySha256: String,
        requestTime: String,
        client: String,
    ): JSONObject =
        JSONObject()
            .put("types", JSONObject()
                .put("EIP712Domain", JSONArray()
                    .put(typeField("name", "string"))
                    .put(typeField("version", "string"))
                    .put(typeField("chainId", "uint256")))
                .put("AnkyMirrorRequest", JSONArray()
                    .put(typeField("identityVersion", "string"))
                    .put(typeField("account", "address"))
                    .put(typeField("method", "string"))
                    .put(typeField("path", "string"))
                    .put(typeField("bodyHash", "bytes32"))
                    .put(typeField("requestTime", "uint64"))
                    .put(typeField("client", "string"))))
            .put("primaryType", "AnkyMirrorRequest")
            .put("domain", JSONObject()
                .put("name", "Anky")
                .put("version", "1")
                .put("chainId", identity.chainId))
            .put("message", JSONObject()
                .put("identityVersion", WriterIdentity.IdentityVersion)
                .put("account", identity.address)
                .put("method", "POST")
                .put("path", "/anky")
                .put("bodyHash", bodySha256)
                .put("requestTime", requestTime.toLong())
                .put("client", client))

    private fun typeField(name: String, type: String): JSONObject =
        JSONObject().put("name", name).put("type", type)
}
