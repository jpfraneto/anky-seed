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
    case randomFailed
}
