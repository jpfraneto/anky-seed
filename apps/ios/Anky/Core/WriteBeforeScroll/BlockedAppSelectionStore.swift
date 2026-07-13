import Foundation

struct BlockedAppSelectionSnapshot: Codable, Equatable {
    let encodedSelectionData: Data?
    let selectedApplicationCount: Int?
    let selectedCategoryCount: Int?
    let updatedAt: Date

    var hasSelection: Bool {
        encodedSelectionData?.isEmpty == false
            || (selectedApplicationCount ?? 0) > 0
            || (selectedCategoryCount ?? 0) > 0
    }
}

struct BlockedAppSelectionStore {
    private let key = "writeBeforeScroll.blockedAppSelection.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AnkyAppGroupStorage.userDefaults()) {
        self.defaults = defaults
    }

    func load() -> BlockedAppSelectionSnapshot? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder.blockedAppSelectionDecoder.decode(BlockedAppSelectionSnapshot.self, from: data)
    }

    func save(_ snapshot: BlockedAppSelectionSnapshot) {
        guard let data = try? JSONEncoder.blockedAppSelectionEncoder.encode(snapshot) else {
            return
        }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

private extension JSONEncoder {
    static var blockedAppSelectionEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var blockedAppSelectionDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
