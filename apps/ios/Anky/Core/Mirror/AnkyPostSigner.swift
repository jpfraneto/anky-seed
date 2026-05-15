import Foundation
#if SWIFT_PACKAGE
import AnkyProtocol
#endif

struct SignedAnkyPost {
    let publicKey: String
    let signature: String
    let requestTime: String
    let bodySha256: String
}

enum AnkyPostSigner {
    static func canonicalMessage(requestTime: String, bodySha256: String) -> String {
        [
            "ANKY_POST_V1",
            "method:POST",
            "path:/anky",
            "request_time:\(requestTime)",
            "body_sha256:\(bodySha256)"
        ].joined(separator: "\n")
    }

    static func sign(body: Data, identity: WriterIdentity, requestTime: String = Self.nowMs()) throws -> SignedAnkyPost {
        let bodySha256 = AnkyHasher.sha256Hex(body)
        let message = canonicalMessage(requestTime: requestTime, bodySha256: bodySha256)
        return SignedAnkyPost(
            publicKey: identity.publicKey,
            signature: try identity.sign(message),
            requestTime: requestTime,
            bodySha256: bodySha256
        )
    }

    private static func nowMs() -> String {
        String(Int64(Date().timeIntervalSince1970 * 1000))
    }
}
