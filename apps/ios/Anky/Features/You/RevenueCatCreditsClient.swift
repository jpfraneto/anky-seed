import Foundation
import RevenueCat

struct RevenueCatCreditPackage: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let price: String
    fileprivate let package: Package
}

enum RevenueCatCreditsConfiguration {
    static let apiKey = "appl_zLWgfNRstPVwqJkIDmhJNReuJtc"
    static let currencyCode = "CRD"
    static let offeringIdentifier = "credits DEV"
    static let productOrder = [
        "inc.dev.anky.credits.22",
        "inc.dev.anky.credits.88_bonus_11",
        "inc.dev.anky.credits.333_bonus_88"
    ]
}

final class RevenueCatCreditsClient {
    @MainActor
    private static var configuredPublicKey: String?

    @MainActor
    func identify(publicKey: String) async throws {
        guard !publicKey.isEmpty else { return }

        if Self.configuredPublicKey == nil {
            #if DEBUG
            Purchases.logLevel = .debug
            #endif
            Purchases.configure(
                withAPIKey: RevenueCatCreditsConfiguration.apiKey,
                appUserID: publicKey
            )
            Self.configuredPublicKey = publicKey
            return
        }

        guard Self.configuredPublicKey != publicKey else {
            return
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Purchases.shared.logIn(publicKey) { _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    Self.configuredPublicKey = publicKey
                    continuation.resume()
                }
            }
        }
    }

    @MainActor
    func fetchCreditBalance() async throws -> Int? {
        let virtualCurrencies = try await Purchases.shared.virtualCurrencies()
        return virtualCurrencies.all[RevenueCatCreditsConfiguration.currencyCode]?.balance
    }

    @MainActor
    func fetchCreditPackages() async throws -> [RevenueCatCreditPackage] {
        let offerings = try await fetchOfferings()
        guard let offering = offerings.offering(identifier: RevenueCatCreditsConfiguration.offeringIdentifier) ?? offerings.current else {
            return []
        }

        let packages = offering.availablePackages.map { package in
            RevenueCatCreditPackage(
                id: package.storeProduct.productIdentifier,
                title: title(for: package.storeProduct.productIdentifier),
                subtitle: package.storeProduct.localizedTitle,
                price: package.storeProduct.localizedPriceString,
                package: package
            )
        }

        return packages.sorted { lhs, rhs in
            let lhsIndex = RevenueCatCreditsConfiguration.productOrder.firstIndex(of: lhs.id) ?? Int.max
            let rhsIndex = RevenueCatCreditsConfiguration.productOrder.firstIndex(of: rhs.id) ?? Int.max
            return lhsIndex < rhsIndex
        }
    }

    @MainActor
    func purchase(_ creditPackage: RevenueCatCreditPackage) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Purchases.shared.purchase(package: creditPackage.package) { _, _, error, userCancelled in
                if userCancelled {
                    continuation.resume()
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    Purchases.shared.invalidateVirtualCurrenciesCache()
                    continuation.resume()
                }
            }
        }
    }

    @MainActor
    private func fetchOfferings() async throws -> Offerings {
        try await withCheckedThrowingContinuation { continuation in
            Purchases.shared.getOfferings { offerings, error in
                if let offerings {
                    continuation.resume(returning: offerings)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: RevenueCatCreditsError.missingOfferings)
                }
            }
        }
    }

    @MainActor
    private func title(for productIdentifier: String) -> String {
        switch productIdentifier {
        case "inc.dev.anky.credits.22":
            return "22 credits"
        case "inc.dev.anky.credits.88_bonus_11":
            return "99 credits"
        case "inc.dev.anky.credits.333_bonus_88":
            return "421 credits"
        default:
            return "credits"
        }
    }
}

enum RevenueCatCreditsError: LocalizedError {
    case missingOfferings

    var errorDescription: String? {
        switch self {
        case .missingOfferings:
            return "RevenueCat did not return a credits offering."
        }
    }
}
