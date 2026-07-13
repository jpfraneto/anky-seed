import Foundation

/// The expandable Face ID / privacy-lock explainer state.
struct PrivacyLockDisclosure: Equatable {
    private(set) var isExpanded = false

    mutating func toggle() {
        isExpanded.toggle()
    }
}
