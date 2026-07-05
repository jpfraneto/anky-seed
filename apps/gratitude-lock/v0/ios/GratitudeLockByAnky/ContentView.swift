import SwiftUI
import UIKit

enum GratitudeSubmission {
    case text(String)
    case voice(URL)
    case image(UIImage)
}

private enum AppPhase {
    case ritual
    case reflection(GratitudeSubmission)
    case rest

    var animationKey: String {
        switch self {
        case .ritual:
            return "ritual"
        case .reflection:
            return "reflection"
        case .rest:
            return "rest"
        }
    }
}

struct ContentView: View {
    @State private var phase: AppPhase = .ritual

    var body: some View {
        ZStack {
            switch phase {
            case .ritual:
                RitualView { submission in
                    withAnimation(.easeInOut(duration: 0.7)) {
                        phase = .reflection(submission)
                    }
                }
                .transition(.opacity)

            case .reflection(let submission):
                ReflectionView(submission: submission) {
                    withAnimation(.easeInOut(duration: 0.9)) {
                        phase = .rest
                    }
                }
                .transition(.opacity)

            case .rest:
                RestOfAppView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.7), value: phase.animationKey)
    }
}
