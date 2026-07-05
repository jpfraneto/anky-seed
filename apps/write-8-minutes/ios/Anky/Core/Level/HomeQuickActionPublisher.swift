import Foundation
#if canImport(UIKit)
import UIKit

/// Phase-2 §3: the one line Anky gets to say on the app icon's long-press
/// menu — sitting above "Remove App", honest and tender, never a siren.
/// Refreshed whenever the app leaves the foreground so the numbers are
/// always true after every sealed session and level-up.
enum HomeQuickActionPublisher {
    static let shortcutType = "inc.anky.openPainting"

    @MainActor
    static func refresh(
        progressStore: LevelProgressStore = LevelProgressStore(),
        entitled: Bool = true
    ) {
        // Phase-3: presented progress only — the boundary line is one line,
        // tender and truthful, deep-linking to the veiled ceremony.
        let progress = progressStore.presentedProgress(entitled: entitled)
        let atBoundary = progressStore.isAtBoundary(entitled: entitled)
        let percent = Int((progress.percent * 100).rounded())
        let freshLevel = progress.secondsIntoLevel <= 0

        let title: String
        let subtitle: String?
        if atBoundary {
            title = AnkyCopyRegistry.boundaryQuickAction
            subtitle = nil
        } else if freshLevel {
            title = AnkyCopyRegistry.quickActionNewPainting
            subtitle = AnkyCopyRegistry.quickActionNewLevelLine(level: progress.level)
        } else {
            title = AnkyCopyRegistry.quickActionUnfinished
            subtitle = AnkyCopyRegistry.quickActionProgressLine(percent: percent, level: progress.level)
        }

        let item = UIApplicationShortcutItem(
            type: shortcutType,
            localizedTitle: title,
            localizedSubtitle: subtitle,
            icon: UIApplicationShortcutIcon(systemImageName: "hurricane"),
            userInfo: ["url": "anky://painting" as NSString]
        )
        UIApplication.shared.shortcutItems = [item]
    }
}

/// Carries a tapped quick action into the SwiftUI world: warm taps post a
/// notification, cold launches park the URL until AppRoot appears.
enum AnkyQuickActionRouter {
    private static var pendingURL: URL?

    static func handle(_ item: UIApplicationShortcutItem) {
        guard item.type == HomeQuickActionPublisher.shortcutType,
              let urlString = item.userInfo?["url"] as? String,
              let url = URL(string: urlString) else {
            return
        }
        pendingURL = url
        NotificationCenter.default.post(name: .ankyQuickActionTapped, object: nil)
    }

    @MainActor
    static func consumePendingURL() -> URL? {
        defer { pendingURL = nil }
        return pendingURL
    }
}

extension Notification.Name {
    static let ankyQuickActionTapped = Notification.Name("anky.quickActionTapped")
}
#endif
