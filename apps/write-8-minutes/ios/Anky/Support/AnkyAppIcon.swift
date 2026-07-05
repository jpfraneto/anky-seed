import SwiftUI

/// One consistent visual language for blocked apps, everywhere a display
/// name is known (the gate intercept carries `attemptedAppDisplayName`).
/// Maps common app names onto the bundled icon set; unknown apps get the
/// quiet door glyph. Extend `iconNames` as new icons land in the catalog.
enum AnkyAppIcon {
    private static let iconNames: [String: String] = [
        "chatgpt": "blocked-chatgpt",
        "chrome": "blocked-chrome",
        "google chrome": "blocked-chrome",
        "claude": "blocked-claude",
        "discord": "blocked-discord",
        "facebook": "blocked-facebook",
        "instagram": "blocked-instagram",
        "linkedin": "blocked-linkedin",
        "netflix": "blocked-netflix",
        "reddit": "blocked-reddit",
        "snapchat": "blocked-snapchat",
        "spotify": "blocked-spotify",
        "telegram": "blocked-telegram",
        "tiktok": "blocked-tiktok",
        "whatsapp": "blocked-whatsapp",
        "x": "blocked-x",
        "twitter": "blocked-x",
        "youtube": "blocked-youtube",
    ]

    static func imageName(forAppNamed name: String?) -> String? {
        guard let name else { return nil }
        let normalized = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return iconNames[normalized]
    }
}

/// The icon view: bundled art when we recognize the app, an ajar-door glyph
/// otherwise. Never judgmental, never a red badge.
struct AnkyAppIconView: View {
    let appName: String?
    var side: CGFloat = 34

    var body: some View {
        Group {
            if let imageName = AnkyAppIcon.imageName(forAppNamed: appName) {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "door.left.hand.closed")
                    .font(.system(size: side * 0.5, weight: .light))
                    .foregroundStyle(Color.ankyInkSoft)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
                .strokeBorder(Color.ankyInk.opacity(0.08), lineWidth: 0.5)
        )
    }
}
