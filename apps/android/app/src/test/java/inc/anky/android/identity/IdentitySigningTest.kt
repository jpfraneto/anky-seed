package inc.anky.android.identity

import inc.anky.android.core.identity.AnkyPostSigner
import inc.anky.android.core.identity.RecoveryPhrase
import inc.anky.android.core.identity.WriterIdentity
import inc.anky.android.core.protocol.AnkyHasher
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class IdentitySigningTest {
    private val fixtureMnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    private val fixtureBody = "1770000000000 anky base identity fixture\n" +
        "0042 exact bytes stay local\n" +
        "0091 mirror signs the hash\n" +
        "8000\n"

    @Test
    fun mnemonicDerivesBaseAccountFixture() {
        val identity = WriterIdentity.fromRecoveryPhrase(RecoveryPhrase.parse(fixtureMnemonic))

        assertEquals("0x9858EfFD232B4033E47d90003D41EC34EcaEda94", identity.address)
        assertEquals("0x9858EfFD232B4033E47d90003D41EC34EcaEda94", identity.accountId)
        assertEquals("anky.base.eoa.v1", identity.descriptor.identityVersion)
        assertEquals("eip712", identity.descriptor.signingScheme)
        assertEquals("secp256k1", identity.descriptor.curve)
        assertEquals("m/44'/60'/0'/0/0", identity.descriptor.derivationPath)
    }

    @Test
    fun signerHashesExactBodyBytesAsBytes32() {
        val identity = WriterIdentity.fromRecoveryPhrase(RecoveryPhrase.parse(fixtureMnemonic))
        val body = fixtureBody.toByteArray(Charsets.UTF_8)
        val signed = AnkyPostSigner.sign(body, identity, "1770000000000", "ios")

        assertEquals("0x${AnkyHasher.sha256Hex(body)}", signed.bodySha256)
        assertEquals("0x77df436eaa64911a72bb961a0fca0ff8b6cf5d7e1abb9bc0e8041dc170348e69", signed.bodySha256)
        assertTrue(signed.signature.startsWith("0x"))
        assertEquals(132, signed.signature.length)
        assertEquals(
            "0xea72c87834c9da6f8078abbeadb948874f6a77c82e1cff5f53d1de622a4884f95ee67809a292e2ee421bac02eab499350ecb9eb31fcdbc821b3737af0b0127f61c",
            signed.signature,
        )
        assertFalse(signed.bodySha256.endsWith(" "))
    }

    @Test
    fun recoveryPhraseRestoresSameAccount() {
        val first = WriterIdentity.fromRecoveryPhrase(RecoveryPhrase.parse(fixtureMnemonic))
        val second = WriterIdentity.fromRecoveryPhrase(RecoveryPhrase.parse(fixtureMnemonic))

        assertEquals(first.address, second.address)
        assertEquals(first.accountId, second.accountId)
    }
}
