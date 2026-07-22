import SwiftUI
import UIKit
import UserNotifications

@main
struct AnkyApp: App {
    @UIApplicationDelegateAdaptor(AnkyAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            AppRoot()
        }
    }
}

final class AnkyAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Before ANYTHING touches state: a fresh install starts over (user
        // decision, 2026-07-17 — "the fresh eyes of a newborn").
        FreshInstallGuard.refreshIfFreshInstall()
        UNUserNotificationCenter.current().delegate = self
        AnkyFraunces.register()
        // A session written in the App Clip before the install: claim it from
        // the handoff container into normal session storage (the same path a
        // natively written session takes). This lives in the delegate — not a
        // view's onAppear — so it runs on every launch surface, including the
        // Geshtu world that bypasses the legacy root.
        if ClipSessionImporter().claimPendingClipSession() != nil {
            UserDefaults.standard.set(true, forKey: ClipSessionImporter.pendingWelcomeDefaultsKey)
        }
        return true
    }

    /// Routes Home Screen quick actions (phase-2 §3): cold launches park the
    /// shortcut before SwiftUI exists; warm taps arrive in the scene delegate.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let shortcutItem = options.shortcutItem {
            AnkyQuickActionRouter.handle(shortcutItem)
        }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = AnkySceneDelegate.self
        return configuration
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard userInfo["route"] as? String == "writeBeforeScroll" else {
            return
        }
        let intentID = userInfo["intentID"] as? String
        WriteBeforeScrollEventLogStore().append(
            .notificationTapped,
            metadata: ["intentID": intentID ?? ""]
        )
        await MainActor.run {
            NotificationCenter.default.post(
                name: .writeBeforeScrollNotificationTapped,
                object: nil,
                userInfo: ["intentID": intentID ?? ""]
            )
        }
    }
}

final class AnkySceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        AnkyQuickActionRouter.handle(shortcutItem)
        completionHandler(true)
    }
}

extension Notification.Name {
    static let writeBeforeScrollNotificationTapped = Notification.Name("writeBeforeScroll.notificationTapped")
}

/// A fresh install starts over (user decision, 2026-07-17): reinstalling the
/// app must feel like a newborn's first open, but iOS lets three things
/// outlive an uninstall — the keychain (identity), the App Group container
/// (shield/unlock/widget state), and, on simulators, a cfprefsd-cached
/// standard-defaults domain. This guard detects the first launch of an
/// install by a marker FILE (files never survive uninstall, on device or
/// simulator) and clears that residue before any other code reads it.
///
/// The App Clip handoff container is deliberately NOT touched: a brand-new
/// writer's first session arrives through it.
///
/// The identity wipe (keychain + its iCloud backup) is DEBUG-only: in
/// Release, identity persistence across reinstall is the writer's recovery
/// path — deleting it would orphan their subscription and server history.
enum FreshInstallGuard {
    private static var markerURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Anky/install-marker.v1")
    }

    static func refreshIfFreshInstall(fileManager: FileManager = .default) {
        let marker = markerURL
        guard !fileManager.fileExists(atPath: marker.path) else {
            return
        }

        // Standard defaults: empty on a true device fresh install, but the
        // simulator can resurrect the old domain across reinstall — and its
        // cfprefsd keeps serving the removed domain to this very process, so
        // the domain removal is followed by key-by-key removal, which the
        // cache does honor.
        if let bundleID = Bundle.main.bundleIdentifier {
            let defaults = UserDefaults.standard
            defaults.removePersistentDomain(forName: bundleID)
            for key in defaults.dictionaryRepresentation().keys {
                defaults.removeObject(forKey: key)
            }
        }

        // The Write Before Scroll App Group survives uninstall: shield
        // selection tokens, unlock state, event log, widget snapshots. iOS
        // clears the actual managed-settings shield when the app is removed;
        // this clears our record of it.
        if let groupDefaults = UserDefaults(suiteName: AnkyAppGroupStorage.identifier) {
            groupDefaults.removePersistentDomain(forName: AnkyAppGroupStorage.identifier)
        }
        if let container = AnkyAppGroupStorage.containerURL() {
            wipeContents(of: container, fileManager: fileManager)
        }

        #if DEBUG
        // The newborn's eyes: a debug install also forgets who it was. This
        // deletes the writer identity INCLUDING its iCloud keychain backup —
        // export the recovery phrase first if the identity on this device
        // matters to you. The onboarding animatic replays too.
        try? WriterIdentityStore().resetForDevelopment(includeICloudBackup: true)
        OnboardingAnimaticLedger.reset()
        #endif

        try? fileManager.createDirectory(
            at: marker.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        fileManager.createFile(atPath: marker.path, contents: Data("born \(Date())".utf8))
    }

    private static func wipeContents(of directory: URL, fileManager: FileManager) {
        let contents = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        for url in contents where url.lastPathComponent != "Library" {
            try? fileManager.removeItem(at: url)
        }
    }
}
    
