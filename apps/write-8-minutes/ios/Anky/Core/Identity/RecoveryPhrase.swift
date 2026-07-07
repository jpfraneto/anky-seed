import CryptoKit
import Foundation
import Security

struct RecoveryPhrase: Hashable {
    let words: [String]

    var text: String {
        words.joined(separator: " ")
    }

    init(words: [String]) throws {
        guard words.count == 12 else {
            throw RecoveryPhraseError.invalidWordCount
        }
        let allowed = Set(BIP39WordList.english)
        guard words.allSatisfy({ allowed.contains($0) }) else {
            throw RecoveryPhraseError.unknownWord
        }
        self.words = words
    }

    init(text: String) throws {
        let words = text
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        try self.init(words: words)
    }

    /// For phrases typed by a human (import): a dictionary-valid one-word
    /// typo must fail here instead of silently deriving a stranger wallet.
    /// Stored phrases keep loading through the non-validating inits so a
    /// pre-validation import can never brick an existing identity.
    init(text: String, validatingChecksum: Bool) throws {
        try self.init(text: text)
        if validatingChecksum, !hasValidChecksum {
            throw RecoveryPhraseError.invalidChecksum
        }
    }

    /// BIP39: the final 4 bits of a 12-word phrase are the top 4 bits of
    /// SHA256 over its 128 entropy bits.
    var hasValidChecksum: Bool {
        guard words.count == 12 else {
            return false
        }
        var bits = [Bool]()
        bits.reserveCapacity(132)
        for word in words {
            guard let index = BIP39WordList.english.firstIndex(of: word) else {
                return false
            }
            for bit in 0..<11 {
                bits.append((index >> (10 - bit)) & 1 == 1)
            }
        }
        var entropy = Data(count: 16)
        for (position, bit) in bits.prefix(128).enumerated() where bit {
            entropy[position / 8] |= 1 << (7 - (position % 8))
        }
        let checksumByte = Data(SHA256.hash(data: entropy))[0]
        for (offset, bit) in bits.suffix(4).enumerated() {
            let expected = (checksumByte >> (7 - offset)) & 1 == 1
            if bit != expected {
                return false
            }
        }
        return true
    }

    static func generate() throws -> RecoveryPhrase {
        var entropy = Data(count: 16)
        let status = entropy.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw RecoveryPhraseError.randomFailed
        }

        var bits = entropy.reduce(into: [Bool]()) { result, byte in
            result.append(contentsOf: (0..<8).map { bit in ((byte >> (7 - bit)) & 1) == 1 })
        }
        let checksum = Data(SHA256.hash(data: entropy))
        let checksumByte = checksum[checksum.startIndex]
        bits.append((checksumByte & 0b1000_0000) != 0)
        bits.append((checksumByte & 0b0100_0000) != 0)
        bits.append((checksumByte & 0b0010_0000) != 0)
        bits.append((checksumByte & 0b0001_0000) != 0)

        let words = stride(from: 0, to: bits.count, by: 11).map { offset in
            var index = 0
            for bit in bits[offset..<(offset + 11)] {
                index = (index << 1) | (bit ? 1 : 0)
            }
            return BIP39WordList.english[index]
        }
        return try RecoveryPhrase(words: words)
    }
}

enum RecoveryPhraseError: Error, Equatable {
    case invalidWordCount
    case unknownWord
    case invalidChecksum
    case randomFailed
}
