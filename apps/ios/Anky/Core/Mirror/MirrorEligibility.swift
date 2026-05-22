import Foundation

enum MirrorEligibility {
    static func canAskAnky(isComplete: Bool, hasReflection: Bool) -> Bool {
        isComplete && !hasReflection
    }
}

enum ReflectionCreditPromptState: Equatable {
    case available(Int)
    case freeGift(Int)
    case unavailable
    case unknown
}

enum ReflectionCreditPresentation {
    static let firstGiftCount = 8

    static func state(
        creditsRemaining: Int?,
        hasClaimedFreeCredits: Bool,
        creditsDenied: Bool = false
    ) -> ReflectionCreditPromptState {
        if creditsDenied {
            return .unavailable
        }
        if let creditsRemaining {
            if creditsRemaining > 0 {
                return .available(creditsRemaining)
            }
            return hasClaimedFreeCredits ? .unavailable : .freeGift(firstGiftCount)
        }
        return hasClaimedFreeCredits ? .unknown : .freeGift(firstGiftCount)
    }

    static func message(for state: ReflectionCreditPromptState) -> String {
        switch state {
        case .available(let count):
            return "You have \(count) \(count == 1 ? "reflection" : "reflections") left"
        case .freeGift(let count):
            return "Anky gives you \(count) free reflections"
        case .unavailable:
            return "No reflections left"
        case .unknown:
            return "Reflection balance updates after mirroring"
        }
    }
}
