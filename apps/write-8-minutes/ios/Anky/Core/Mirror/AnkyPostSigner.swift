import BigInt
import CryptoKit
import CryptoSwift
import Foundation

#if SWIFT_PACKAGE
import AnkyProtocol
#endif

struct SignedAnkyPost {
    let identityVersion: String
    let accountId: String
    let signatureType: String
    let signature: String
    let requestTime: String
    let client: String
    let bodySha256: String
    let eip712Digest: String
}

enum AnkyPostSigner {
    static let domainType = "EIP712Domain(string name,string version,uint256 chainId)"
    static let requestType = "AnkyMirrorRequest(string identityVersion,address account,string method,string path,bytes32 bodyHash,uint64 requestTime,string client)"

    static func sign(
        body: Data,
        identity: WriterIdentity,
        requestTime: UInt64 = Self.nowMs(),
        client: String = "ios"
    ) throws -> SignedAnkyPost {
        let bodySha256 = AnkyHasher.sha256Hex(body).addHexPrefix()
        let digest = try eip712Digest(
            identity: identity,
            bodySha256: bodySha256,
            requestTime: requestTime,
            client: client
        )
        return SignedAnkyPost(
            identityVersion: WriterIdentity.identityVersion,
            accountId: identity.accountId,
            signatureType: WriterIdentity.signingScheme,
            signature: try identity.signDigest(digest),
            requestTime: String(requestTime),
            client: client,
            bodySha256: bodySha256,
            eip712Digest: digest.toHexString().addHexPrefix()
        )
    }

    static func eip712Digest(
        identity: WriterIdentity,
        bodySha256: String,
        requestTime: UInt64,
        client: String
    ) throws -> Data {
        let domainSeparator = keccak(
            keccak(Data(domainType.utf8)) +
            encodeString("Anky") +
            encodeString("1") +
            encodeUInt(identity.chainId)
        )

        let requestHash = try keccak(
            keccak(Data(requestType.utf8)) +
            encodeString(WriterIdentity.identityVersion) +
            encodeAddress(identity.address) +
            encodeString("POST") +
            encodeString("/anky") +
            encodeBytes32(bodySha256) +
            encodeUInt(requestTime) +
            encodeString(client)
        )

        return keccak(Data([0x19, 0x01]) + domainSeparator + requestHash)
    }

    private static func nowMs() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1000)
    }

    private static func keccak(_ data: Data) -> Data {
        data.sha3(.keccak256)
    }

    private static func encodeString(_ value: String) -> Data {
        keccak(Data(value.utf8))
    }

    private static func encodeAddress(_ value: String) throws -> Data {
        guard let address = Data.fromHex(value), address.count == 20 else {
            throw AnkyPostSignerError.invalidAddress
        }
        return pad32(address)
    }

    private static func encodeBytes32(_ value: String) throws -> Data {
        guard let bytes = Data.fromHex(value), bytes.count == 32 else {
            throw AnkyPostSignerError.invalidBodyHash
        }
        return bytes
    }

    private static func encodeUInt(_ value: UInt64) -> Data {
        pad32(BigUInt(value).serialize())
    }

    private static func pad32(_ data: Data) -> Data {
        guard data.count < 32 else {
            return data
        }
        return Data(repeating: 0, count: 32 - data.count) + data
    }
}

enum AnkyPostSignerError: Error, Equatable {
    case invalidAddress
    case invalidBodyHash
}
