import Foundation

enum MirrorEligibility {
    static func canAskAnky(isComplete: Bool, hasReflection: Bool) -> Bool {
        isComplete && !hasReflection
    }
}
