import WidgetKit
import SwiftUI

/// Phase-2 §4/§5: the glance surfaces — the painting widget and the honest
/// trial Live Activity. Everything here only reads what the app mirrored
/// into the App Group; no writing, no counters, no flame.
@main
struct AnkyGlanceWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PaintingWidget()
        TrialLiveActivity()
    }
}

/// The design language, as literals — the extension deliberately compiles
/// no app theme code. Values mirror DESIGN.md §7 / AnkyLazure.swift.
enum GlancePalette {
    static let paper = Color(.displayP3, red: 0.965, green: 0.937, blue: 0.894)
    static let paperDeep = Color(.displayP3, red: 0.929, green: 0.882, blue: 0.835)
    static let ink = Color(.displayP3, red: 0.239, green: 0.216, blue: 0.310)
    static let inkSoft = Color(.displayP3, red: 0.396, green: 0.369, blue: 0.475)
    static let gold = Color(.displayP3, red: 0.878, green: 0.694, blue: 0.427)
    static let goldLight = Color(.displayP3, red: 0.965, green: 0.847, blue: 0.631)
}
