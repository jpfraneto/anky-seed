import Foundation

enum Base58 {
    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    private static let indexes = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($0.element, $0.offset) })

    static func encode(_ data: Data) -> String {
        guard !data.isEmpty else {
            return ""
        }

        var digits = [Int](repeating: 0, count: 1)
        for byte in data {
            var carry = Int(byte)
            for index in digits.indices {
                let value = digits[index] * 256 + carry
                digits[index] = value % 58
                carry = value / 58
            }

            while carry > 0 {
                digits.append(carry % 58)
                carry /= 58
            }
        }

        var result = String(data.prefix { $0 == 0 }.map { _ in alphabet[0] })
        for digit in digits.reversed() {
            result.append(alphabet[digit])
        }
        return result
    }

    static func decode(_ string: String) -> Data? {
        guard !string.isEmpty else {
            return Data()
        }

        var bytes = [Int](repeating: 0, count: 1)
        for character in string {
            guard let value = indexes[character] else {
                return nil
            }

            var carry = value
            for index in bytes.indices {
                let next = bytes[index] * 58 + carry
                bytes[index] = next & 0xff
                carry = next >> 8
            }

            while carry > 0 {
                bytes.append(carry & 0xff)
                carry >>= 8
            }
        }

        var decodedBytes = bytes.reversed().map(UInt8.init)
        while decodedBytes.first == 0 {
            decodedBytes.removeFirst()
        }

        let leadingZeros = string.prefix { $0 == alphabet[0] }.count
        var decoded = Data(repeating: 0, count: leadingZeros)
        decoded.append(contentsOf: decodedBytes)
        return decoded
    }
}
