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
        UNUserNotificationCenter.current().delegate = self
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
    
