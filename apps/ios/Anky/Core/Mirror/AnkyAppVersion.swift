import Foundation

/// The X-Anky-App-Version header value: "1.2(34)".
enum AnkyAppVersion {
    static var headerValue: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        return "\(version)(\(build))"
    }
}
