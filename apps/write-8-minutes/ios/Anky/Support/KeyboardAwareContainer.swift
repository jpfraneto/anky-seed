import SwiftUI
import UIKit

/// The global keyboard-aware layout container: nothing placed inside is
/// ever occluded by the keyboard. Content is inset by the live keyboard
/// overlap and the change animates with the keyboard's own curve.
///
/// Use on any screen that can coexist with the keyboard (onboarding
/// thresholds, prompts over the writing surface, forms).
struct KeyboardAwareContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @State private var keyboardOverlap: CGFloat = 0

    var body: some View {
        content()
            .padding(.bottom, keyboardOverlap)
            .ignoresSafeArea(.keyboard)
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIResponder.keyboardWillChangeFrameNotification
                )
            ) { notification in
                update(from: notification)
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIResponder.keyboardWillHideNotification
                )
            ) { notification in
                update(from: notification, hidden: true)
            }
    }

    private func update(from notification: Notification, hidden: Bool = false) {
        let overlap: CGFloat
        if hidden {
            overlap = 0
        } else if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            overlap = max(0, UIScreen.main.bounds.maxY - frame.minY)
        } else {
            overlap = 0
        }
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        withAnimation(.easeOut(duration: max(0.16, duration ?? 0.24))) {
            keyboardOverlap = overlap
        }
    }
}
