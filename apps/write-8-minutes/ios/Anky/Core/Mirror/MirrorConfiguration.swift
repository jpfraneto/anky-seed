import Foundation

enum MirrorConfiguration {
    static let userDefaultsKey = "mirrorBaseURL"
    static let defaultBaseURL = "https://mirror-production-a23c.up.railway.app"

    static func currentBaseURL(defaults: UserDefaults = .standard) -> String {
        let value = defaults.string(forKey: userDefaultsKey) ?? defaultBaseURL
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultBaseURL : value
    }
}
