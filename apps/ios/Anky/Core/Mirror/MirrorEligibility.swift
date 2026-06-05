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
    static let firstGiftCount = 1

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
        return hasClaimedFreeCredits ? .unavailable : .freeGift(firstGiftCount)
    }

    static func message(for state: ReflectionCreditPromptState) -> String {
        switch state {
        case .available(let count):
            return "You have \(count) \(count == 1 ? "reflection" : "reflections") left"
        case .freeGift(let count):
            return "\(count) \(count == 1 ? "reflection" : "reflections") available on this device"
        case .unavailable:
            return "No reflections left"
        case .unknown:
            return "Reflection balance updates after mirroring"
        }
    }
}

enum ReflectionCreditCache {
    private static let claimedKey = "anky.hasClaimedFreeReflections"
    private static let balanceKey = "anky.reflectionCreditBalance"

    static func hasClaimedFreeCredits(accountId: String, defaults: UserDefaults = .standard) -> Bool {
        if !accountId.isEmpty, defaults.bool(forKey: claimedKeyForAccount(accountId)) {
            return true
        }
        return defaults.bool(forKey: claimedKey)
    }

    static func markFreeCreditsClaimed(accountId: String, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: claimedKey)
        if !accountId.isEmpty {
            defaults.set(true, forKey: claimedKeyForAccount(accountId))
        }
    }

    static func balance(accountId: String, defaults: UserDefaults = .standard) -> Int? {
        let key = balanceKeyForAccount(accountId)
        guard defaults.object(forKey: key) != nil else {
            return nil
        }
        return defaults.integer(forKey: key)
    }

    static func storeBalance(_ balance: Int?, accountId: String, defaults: UserDefaults = .standard) {
        let key = balanceKeyForAccount(accountId)
        guard let balance else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(balance, forKey: key)
    }

    static func clear(defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys {
            if key == claimedKey || key.hasPrefix("\(claimedKey).") || key.hasPrefix("\(balanceKey).") {
                defaults.removeObject(forKey: key)
            }
        }
    }

    private static func claimedKeyForAccount(_ accountId: String) -> String {
        "\(claimedKey).\(accountId)"
    }

    private static func balanceKeyForAccount(_ accountId: String) -> String {
        "\(balanceKey).\(accountId)"
    }
}
