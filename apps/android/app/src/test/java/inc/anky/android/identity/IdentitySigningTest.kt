package inc.anky.android.identity

import inc.anky.android.core.identity.AnkyPostSigner
import inc.anky.android.core.identity.Base58
import inc.anky.android.core.identity.RecoveryPhrase
import inc.anky.android.core.identity.WriterIdentity
import inc.anky.android.core.protocol.AnkyHasher
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class IdentitySigningTest {
    @Test
    fun base58PreservesLeadingZeroBytes() {
        val bytes = byteArrayOf(0, 0, 1, 2, 3)
        val encoded = Base58.encode(bytes)
        assertTrue(encoded.startsWith("11"))
        assertEquals(bytes.toList(), Base58.decode(encoded)?.toList())
    }

    @Test
    fun canonicalMessageMatchesBackendContract() {
        assertEquals(
            listOf(
                "ANKY_POST_V1",
                "method:POST",
                "path:/anky",
                "request_time:1770000000000",
                "body_sha256:abc123",
            ).joinToString("\n"),
            AnkyPostSigner.canonicalMessage("1770000000000", "abc123"),
        )
    }

    @Test
    fun ed25519SignatureVerifiesWithBase58PublicKeyAndSignature() {
        val phrase = RecoveryPhrase.parse("able about above absent absorb abstract access accident account across action actual")
        val identity = WriterIdentity.fromRecoveryPhrase(phrase)
        val message = AnkyPostSigner.canonicalMessage("1770000000000", "abc123")
        val signature = identity.sign(message)

        assertEquals(32, Base58.decode(identity.publicKey)?.size)
        assertEquals(64, Base58.decode(signature)?.size)
        assertTrue(identity.verifies(message, signature))
        assertFalse(identity.verifies("$message\n", signature))
    }

    @Test
    fun identityMatchesBackendNobleEd25519Vector() {
        val phrase = RecoveryPhrase.parse("able about above absent absorb abstract access accident account across action actual")
        val identity = WriterIdentity.fromRecoveryPhrase(phrase)
        val message = AnkyPostSigner.canonicalMessage("1770000000000", "abc123")

        assertEquals("MQ5arRxphfMgDoheq3LPVN2sqFuZt3HwKPkb3kDFhoM", identity.publicKey)
        assertEquals(
            "66ndLcazKT7Ecn22GipqXs5rBhvyVURNY9dF57T4PZ4z3eMtC3M6BnB3EJraBjXM9zQwuZ5vQatSwwrc8gcJdZjx",
            identity.sign(message),
        )
    }

    @Test
    fun signerHashesExactBodyBytes() {
        val phrase = RecoveryPhrase.parse("able about above absent absorb abstract access accident account across action actual")
        val identity = WriterIdentity.fromRecoveryPhrase(phrase)
        val body = "1770000000000 h\n0042 e\n8000".toByteArray(Charsets.UTF_8)
        val signed = AnkyPostSigner.sign(body, identity, "1770000000000")

        assertEquals(AnkyHasher.sha256Hex(body), signed.bodySha256)
        assertTrue(identity.verifies(AnkyPostSigner.canonicalMessage(signed.requestTime, signed.bodySha256), signed.signature))
    }
}
