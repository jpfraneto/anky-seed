import SwiftUI

/// The app's root view.
///
/// Anky is one vertical world organized around a single fixed point, and
/// `GeshtuWorldView` is that world — it owns every surface the app can show
/// (writing, the crossroads, the reflection descent, the strata, the seed).
/// The root exists only to hand SwiftUI that world.
///
/// History: this file used to carry a second, parallel app — a tab bar over
/// a `selectedTab` / `writeSurface` router with its own home, check-in,
/// sealing, archive, profile and ceremony surfaces — behind a hardcoded
/// `geshtuWorldEnabled = true`. None of it could render, but the root still
/// built all seven of its view models on every launch (one of them deriving
/// the writer's account key from its recovery words, ~410ms in a debug build)
/// before the first frame. That path is gone; see git history for it.
struct AppRoot: View {
    var body: some View {
        GeshtuWorldView()
    }
}
