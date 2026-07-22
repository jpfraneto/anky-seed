import SwiftUI

/// The Anky App Clip: one raw writing session, then the handoff.
///
/// Someone taps a link and lands directly on a live writing surface. They
/// write, the sentinel fires, the session seals into the shared handoff
/// container, and the full app claims it on first launch. No onboarding, no
/// identity, no networking, no second screen.
@main
struct AnkyClipApp: App {
    @StateObject private var session = ClipSessionController()

    init() {
        AnkyFraunces.register()
    }

    var body: some Scene {
        WindowGroup {
            ClipWriteView(session: session)
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    session.handleInvocation(url: activity.webpageURL)
                }
                .onOpenURL { url in
                    session.handleInvocation(url: url)
                }
        }
    }
}
