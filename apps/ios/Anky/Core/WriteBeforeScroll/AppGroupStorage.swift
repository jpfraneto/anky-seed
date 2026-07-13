import Foundation

enum AnkyAppGroupStorage {
    static let identifier = "group.com.jpfraneto.Anky"

    static func userDefaults() -> UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    static func containerURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
