import Foundation

enum FreeCreditMessage {
    static func make(accountId: String, appVersion: String?) -> String {
        var lines = [
            "hey jp, i'd love to try anky reflections.",
            "",
            "my Anky address is:",
            accountId,
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

struct PrivacyLockDisclosure: Equatable {
    private(set) var isExpanded = false

    mutating func toggle() {
        isExpanded.toggle()
    }
}
