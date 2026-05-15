import Foundation

enum FreeCreditMessage {
    static func make(publicKey: String, appVersion: String?) -> String {
        var lines = [
            "hey jp, i'd love to try anky reflections.",
            "",
            "my public key is:",
            publicKey,
            "",
            "platform: ios"
        ]

        if let appVersion, !appVersion.isEmpty {
            lines.append("")
            lines.append("app version: \(appVersion)")
        }

        return lines.joined(separator: "\n")
    }
}
