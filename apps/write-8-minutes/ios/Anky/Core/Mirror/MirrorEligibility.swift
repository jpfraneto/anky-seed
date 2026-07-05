import Foundation

enum MirrorEligibility {
    static func canAskAnky(isComplete: Bool, hasReflection: Bool) -> Bool {
        !hasReflection
    }
}

enum AnkyReflectionPrompt {
    static func build(from reconstructedText: String) -> String {
        """
        Take a look at this stream-of-consciousness journal entry.

        Respond with deep insight that feels personal, casual, and alive, not clinical. Be a sharp mirror: part close friend, part mentor, part pattern-recognizer.

        Help the writer see the emotional undercurrents, hidden loops, deeper meaning, contradictions, longings, and connections they might be missing.

        Comfort what is real. Validate without flattering. Challenge gently where needed. Reframe the surface topic into what the writer may really be seeking underneath.

        Do not force introspection for its own sake. Help the writer recognize something true about who they are and move toward a more honest, positive loop in life.

        Use vivid metaphors and powerful imagery when they reveal something real. Don't diagnose, don't sound like therapy, and don't give generic advice.

        Write in the same language and vibe as the entry.

        Reply with pure markdown, and use headings for different sections. At the top of the reply add a max 4 word title.

        ---

        \(reconstructedText)
        """
    }
}

enum ReflectionCreditPromptState: Equatable {
    case available(Int)
    case freeGift(Int)
    case unavailable
    case unknown
}

enum ReflectionCreditPresentation {
    static let firstGiftCount = 2

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
