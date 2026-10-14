import CommonCrypto
import CryptoKit
import Foundation
import secp256k1

/// The primitives behind the writer's account key, kept to exactly what
/// Anky uses: derive one secp256k1 key from the 12 recovery words, name it
/// by a 20-byte account id, and sign request digests for the mirror. No
/// network, no chain — the key only authenticates requests to Anky's own
/// server. Byte-compatible with the derivation earlier builds shipped, so
/// existing accounts keep their id.
enum AccountKeyCrypto {
    private static let context = secp256k1_context_create(UInt32(SECP256K1_CONTEXT_SIGN | SECP256K1_CONTEXT_VERIFY))

    // MARK: Recovery words → seed → key (BIP39 / BIP32)

    /// PBKDF2-HMAC-SHA512, 2048 rounds, salt "mnemonic" (no passphrase).
    static func seed(fromPhrase phrase: String) -> Data? {
        let password = Data(phrase.decomposedStringWithCompatibilityMapping.utf8)
        let salt = Data("mnemonic".utf8)
        var seed = Data(count: 64)
        let status = seed.withUnsafeMutableBytes { seedBuffer in
            password.withUnsafeBytes { passwordBuffer in
                salt.withUnsafeBytes { saltBuffer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.baseAddress?.assumingMemoryBound(to: Int8.self),
                        password.count,
                        saltBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
                        2048,
                        seedBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        64
                    )
                }
            }
        }
        return status == kCCSuccess ? seed : nil
    }

    /// Walks a path like "m/44'/60'/0'/0/0" from the seed and returns the
    /// 32-byte private key at its end.
    static func derivePrivateKey(seed: Data, path: String) -> Data? {
        let master = hmacSHA512(key: Data("Bitcoin seed".utf8), data: seed)
        var key = Data(master.prefix(32))
        var chainCode = Data(master.suffix(32))
        guard isValidPrivateKey(key) else { return nil }

        let components = path.split(separator: "/")
        guard components.first == "m" else { return nil }
        for component in components.dropFirst() {
            let hardened = component.hasSuffix("'")
            guard let index = UInt32(hardened ? component.dropLast() : component[...]),
                  index < 0x8000_0000 else {
                return nil
            }
            var data = Data()
            if hardened {
                data.append(0)
                data.append(key)
            } else {
                guard let publicKey = publicKey(privateKey: key, compressed: true) else { return nil }
                data.append(publicKey)
            }
            let childIndex = hardened ? index | 0x8000_0000 : index
            data.append(contentsOf: withUnsafeBytes(of: childIndex.bigEndian, Array.init))

            let derived = hmacSHA512(key: chainCode, data: data)
            guard let childKey = addScalars(key, Data(derived.prefix(32))) else { return nil }
            key = childKey
            chainCode = Data(derived.suffix(32))
        }
        return key
    }

    // MARK: Keys

    static func isValidPrivateKey(_ privateKey: Data) -> Bool {
        guard let context, privateKey.count == 32 else { return false }
        return privateKey.withUnsafeBytes { buffer in
            secp256k1_ec_seckey_verify(context, buffer.bindMemory(to: UInt8.self).baseAddress!) == 1
        }
    }

    static func publicKey(privateKey: Data, compressed: Bool) -> Data? {
        guard let context, isValidPrivateKey(privateKey) else { return nil }
        var publicKey = secp256k1_pubkey()
        let created = privateKey.withUnsafeBytes { buffer in
            secp256k1_ec_pubkey_create(context, &publicKey, buffer.bindMemory(to: UInt8.self).baseAddress!)
        }
        guard created == 1 else { return nil }
        return serialize(&publicKey, compressed: compressed)
    }

    /// 20-byte account id from an uncompressed (65-byte) public key, as a
    /// mixed-case checksummed 0x string.
    static func accountId(uncompressedPublicKey: Data) -> String? {
        guard uncompressedPublicKey.count == 65, uncompressedPublicKey.first == 0x04 else { return nil }
        let raw = keccak256(uncompressedPublicKey.dropFirst()).suffix(20)
        return checksummed(hexLowercase(Data(raw)))
    }

    /// Mixed-case checksum over a 40-hex-character id (with or without 0x).
    static func checksummed(_ hex: String) -> String? {
        let lower = (hex.hasPrefix("0x") || hex.hasPrefix("0X") ? String(hex.dropFirst(2)) : hex).lowercased()
        guard lower.count == 40, data(fromHex: lower) != nil else { return nil }
        let hash = hexLowercase(keccak256(Data(lower.utf8)))
        var result = "0x"
        for (character, hashCharacter) in zip(lower, hash) {
            if character.isLetter, let nibble = hashCharacter.hexDigitValue, nibble >= 8 {
                result.append(character.uppercased())
            } else {
                result.append(character)
            }
        }
        return result
    }

    // MARK: Signatures

    /// Deterministic (RFC 6979) recoverable signature over a 32-byte digest,
    /// serialized r ‖ s ‖ v with v ∈ {27, 28}.
    static func signRecoverable(digest: Data, privateKey: Data) -> Data? {
        guard let context, digest.count == 32, isValidPrivateKey(privateKey) else { return nil }
        var signature = secp256k1_ecdsa_recoverable_signature()
        let signed = digest.withUnsafeBytes { digestBuffer in
            privateKey.withUnsafeBytes { keyBuffer in
                secp256k1_ecdsa_sign_recoverable(
                    context,
                    &signature,
                    digestBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    keyBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    nil,
                    nil
                )
            }
        }
        guard signed == 1 else { return nil }

        var compact = Data(count: 64)
        var recoveryId: Int32 = 0
        let serialized = compact.withUnsafeMutableBytes { buffer in
            secp256k1_ecdsa_recoverable_signature_serialize_compact(
                context,
                buffer.bindMemory(to: UInt8.self).baseAddress!,
                &recoveryId,
                &signature
            )
        }
        guard serialized == 1, recoveryId == 0 || recoveryId == 1 else { return nil }
        compact.append(UInt8(27 + recoveryId))
        return compact
    }

    /// The uncompressed public key that produced `signature` over `digest`.
    static func recoverPublicKey(digest: Data, signature: Data) -> Data? {
        guard let context, digest.count == 32, signature.count == 65 else { return nil }
        var recoveryId = Int32(signature[signature.startIndex + 64])
        if recoveryId >= 27 { recoveryId -= 27 }
        guard recoveryId == 0 || recoveryId == 1 else { return nil }

        var parsed = secp256k1_ecdsa_recoverable_signature()
        let compact = Data(signature.prefix(64))
        let parsedOK = compact.withUnsafeBytes { buffer in
            secp256k1_ecdsa_recoverable_signature_parse_compact(
                context,
                &parsed,
                buffer.bindMemory(to: UInt8.self).baseAddress!,
                recoveryId
            )
        }
        guard parsedOK == 1 else { return nil }

        var publicKey = secp256k1_pubkey()
        let recovered = digest.withUnsafeBytes { buffer in
            secp256k1_ecdsa_recover(context, &publicKey, &parsed, buffer.bindMemory(to: UInt8.self).baseAddress!)
        }
        guard recovered == 1 else { return nil }
        return serialize(&publicKey, compressed: false)
    }

    // MARK: Keccak-256

    static func keccak256<D: DataProtocol>(_ input: D) -> Data {
        var state = [UInt64](repeating: 0, count: 25)
        let rate = 136
        var message = [UInt8](input)
        message.append(0x01)
        while message.count % rate != 0 {
            message.append(0x00)
        }
        message[message.count - 1] |= 0x80

        for blockStart in stride(from: 0, to: message.count, by: rate) {
            for lane in 0..<(rate / 8) {
                var value: UInt64 = 0
                for byte in 0..<8 {
                    value |= UInt64(message[blockStart + lane * 8 + byte]) << (8 * UInt64(byte))
                }
                state[lane] ^= value
            }
            keccakF1600(&state)
        }

        var output = Data(capacity: 32)
        for lane in 0..<4 {
            for byte in 0..<8 {
                output.append(UInt8(truncatingIfNeeded: state[lane] >> (8 * UInt64(byte))))
            }
        }
        return output
    }

    private static let roundConstants: [UInt64] = [
        0x0000_0000_0000_0001, 0x0000_0000_0000_8082, 0x8000_0000_0000_808A, 0x8000_0000_8000_8000,
        0x0000_0000_0000_808B, 0x0000_0000_8000_0001, 0x8000_0000_8000_8081, 0x8000_0000_0000_8009,
        0x0000_0000_0000_008A, 0x0000_0000_0000_0088, 0x0000_0000_8000_8009, 0x0000_0000_8000_000A,
        0x0000_0000_8000_808B, 0x8000_0000_0000_008B, 0x8000_0000_0000_8089, 0x8000_0000_0000_8003,
        0x8000_0000_0000_8002, 0x8000_0000_0000_0080, 0x0000_0000_0000_800A, 0x8000_0000_8000_000A,
        0x8000_0000_8000_8081, 0x8000_0000_0000_8080, 0x0000_0000_8000_0001, 0x8000_0000_8000_8008
    ]

    private static let rotationOffsets: [Int] = [
        0, 1, 62, 28, 27,
        36, 44, 6, 55, 20,
        3, 10, 43, 25, 39,
        41, 45, 15, 21, 8,
        18, 2, 61, 56, 14
    ]

    private static func keccakF1600(_ a: inout [UInt64]) {
        var b = [UInt64](repeating: 0, count: 25)
        var c = [UInt64](repeating: 0, count: 5)
        for round in 0..<24 {
            // θ
            for x in 0..<5 {
                c[x] = a[x] ^ a[x + 5] ^ a[x + 10] ^ a[x + 15] ^ a[x + 20]
            }
            for x in 0..<5 {
                let d = c[(x + 4) % 5] ^ rotl(c[(x + 1) % 5], 1)
                for y in stride(from: 0, to: 25, by: 5) {
                    a[y + x] ^= d
                }
            }
            // ρ and π
            for x in 0..<5 {
                for y in 0..<5 {
                    b[y + 5 * ((2 * x + 3 * y) % 5)] = rotl(a[x + 5 * y], rotationOffsets[x + 5 * y])
                }
            }
            // χ
            for y in stride(from: 0, to: 25, by: 5) {
                for x in 0..<5 {
                    a[y + x] = b[y + x] ^ (~b[y + (x + 1) % 5] & b[y + (x + 2) % 5])
                }
            }
            // ι
            a[0] ^= roundConstants[round]
        }
    }

    private static func rotl(_ value: UInt64, _ shift: Int) -> UInt64 {
        shift == 0 ? value : (value << UInt64(shift)) | (value >> UInt64(64 - shift))
    }

    // MARK: Hex

    static func hexLowercase(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func prefixedHex(_ data: Data) -> String {
        "0x" + hexLowercase(data)
    }

    /// Strict hex decode; accepts an optional 0x prefix, rejects odd length
    /// or non-hex characters.
    static func data(fromHex hex: String) -> Data? {
        let body = hex.hasPrefix("0x") || hex.hasPrefix("0X") ? hex.dropFirst(2) : hex[...]
        guard body.count % 2 == 0 else { return nil }
        var data = Data(capacity: body.count / 2)
        var index = body.startIndex
        while index < body.endIndex {
            let next = body.index(index, offsetBy: 2)
            guard let byte = UInt8(body[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    // MARK: Private

    private static func hmacSHA512(key: Data, data: Data) -> Data {
        Data(HMAC<SHA512>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }

    /// (a + b) mod n, or nil when b ≥ n or the sum is zero.
    private static func addScalars(_ a: Data, _ b: Data) -> Data? {
        guard let context else { return nil }
        var sum = a
        let added = sum.withUnsafeMutableBytes { sumBuffer in
            b.withUnsafeBytes { tweakBuffer in
                secp256k1_ec_seckey_tweak_add(
                    context,
                    sumBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    tweakBuffer.bindMemory(to: UInt8.self).baseAddress!
                )
            }
        }
        return added == 1 ? sum : nil
    }

    private static func serialize(_ publicKey: inout secp256k1_pubkey, compressed: Bool) -> Data? {
        guard let context else { return nil }
        var length = compressed ? 33 : 65
        var output = Data(count: length)
        let flags = UInt32(compressed ? SECP256K1_EC_COMPRESSED : SECP256K1_EC_UNCOMPRESSED)
        let serialized = output.withUnsafeMutableBytes { buffer in
            secp256k1_ec_pubkey_serialize(context, buffer.bindMemory(to: UInt8.self).baseAddress!, &length, &publicKey, flags)
        }
        return serialized == 1 ? output.prefix(length) : nil
    }
}
