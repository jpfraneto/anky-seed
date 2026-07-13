import Foundation
import Security

struct KeychainClient {
    private let service: String

    init(service: String = "lat.memetics.anky") {
        self.service = service
    }

    func data(for account: String, synchronizable: Bool = false) throws -> Data? {
        var query = baseQuery(account: account, synchronizable: synchronizable)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
        return result as? Data
    }

    func save(_ data: Data, account: String, synchronizable: Bool = false) throws {
        var query = baseQuery(account: account, synchronizable: synchronizable)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = synchronizable ? kSecAttrAccessibleAfterFirstUnlock : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let attributes = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery(account: account, synchronizable: synchronizable) as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unhandled(updateStatus)
            }
            return
        }
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    func delete(account: String, synchronizable: Bool = false) throws {
        let status = SecItemDelete(baseQuery(account: account, synchronizable: synchronizable) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    private func baseQuery(account: String, synchronizable: Bool = false) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if synchronizable {
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        }
        return query
    }
}

enum KeychainError: Error, Equatable {
    case unhandled(OSStatus)
}
