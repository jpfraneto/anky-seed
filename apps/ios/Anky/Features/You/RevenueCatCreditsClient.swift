import Foundation
import RevenueCat

struct RevenueCatCreditPackage: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let price: String
    fileprivate let purchaseTarget: RevenueCatCreditPurchaseTarget
}

private enum RevenueCatCreditPurchaseTarget {
    case package(Package)
    case product(StoreProduct)
}

enum RevenueCatCreditPurchaseResult {
    case purchased
    case cancelled
}

enum RevenueCatCreditsConfiguration {
    static let apiKey = "appl_mvCsxolPWZmQjtULGLQhmOUhGMY"
    static let currencyCode = "CRD"
    static let offeringIdentifier = "Credits"
    static let productOrder = [
        "inc.anky.credits.3",
        "inc.anky.credits.11",
        "inc.anky.credits.33"
    ]
}

final class RevenueCatCreditsClient {
    @MainActor
    private static var configuredAccountId: String?

    static func appUserID(for identity: WriterIdentity) -> String {
        CreditIdentity.appUserID(for: identity)
    }

    @MainActor
    func identify(accountId: String) async throws {
        guard !accountId.isEmpty else { return }

        if Self.configuredAccountId == nil {
            #if DEBUG
            Purchases.logLevel = .debug
            #endif
            Purchases.configure(
                withAPIKey: RevenueCatCreditsConfiguration.apiKey,
                appUserID: accountId
            )
            Self.configuredAccountId = accountId
            return
        }

        guard Self.configuredAccountId != accountId else {
            return
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Purchases.shared.logIn(accountId) { _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    Self.configuredAccountId = accountId
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
        let offering = offerings.offering(identifier: RevenueCatCreditsConfiguration.offeringIdentifier) ?? offerings.current
        let offeringPackages = offering?.availablePackages ?? []
        let packageModels = offeringPackages.map(Self.creditPackage)
        let packagedProductIds = Set(packageModels.map(\.id))
        let missingProductIds = RevenueCatCreditsConfiguration.productOrder.filter { !packagedProductIds.contains($0) }

        let directProductModels: [RevenueCatCreditPackage]
        if missingProductIds.isEmpty {
            directProductModels = []
        } else {
            directProductModels = await Purchases.shared.products(missingProductIds).map(Self.creditPackage)
        }

        let packages = packageModels + directProductModels

        return packages
            .uniquedByProductId()
            .sorted { lhs, rhs in
                let lhsIndex = RevenueCatCreditsConfiguration.productOrder.firstIndex(of: lhs.id) ?? Int.max
                let rhsIndex = RevenueCatCreditsConfiguration.productOrder.firstIndex(of: rhs.id) ?? Int.max
                return lhsIndex < rhsIndex
            }
    }

    @MainActor
    func purchase(_ creditPackage: RevenueCatCreditPackage) async throws -> RevenueCatCreditPurchaseResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RevenueCatCreditPurchaseResult, Error>) in
            let completion: PurchaseCompletedBlock = { _, _, error, userCancelled in
                if userCancelled {
                    continuation.resume(returning: .cancelled)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    Purchases.shared.invalidateVirtualCurrenciesCache()
                    continuation.resume(returning: .purchased)
                }
            }

            switch creditPackage.purchaseTarget {
            case .package(let package):
                Purchases.shared.purchase(package: package, completion: completion)
            case .product(let product):
                Purchases.shared.purchase(product: product, completion: completion)
            }
        }
    }

    @MainActor
    func invalidateCreditBalanceCache() {
        Purchases.shared.invalidateVirtualCurrenciesCache()
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

    private static func creditPackage(for package: Package) -> RevenueCatCreditPackage {
        let product = package.storeProduct
        return RevenueCatCreditPackage(
            id: product.productIdentifier,
            title: title(for: product.productIdentifier),
            subtitle: subtitle(for: product.productIdentifier, fallback: product.localizedTitle),
            price: product.localizedPriceString,
            purchaseTarget: .package(package)
        )
    }

    private static func creditPackage(for product: StoreProduct) -> RevenueCatCreditPackage {
        RevenueCatCreditPackage(
            id: product.productIdentifier,
            title: title(for: product.productIdentifier),
            subtitle: subtitle(for: product.productIdentifier, fallback: product.localizedTitle),
            price: product.localizedPriceString,
            purchaseTarget: .product(product)
        )
    }

    private static func title(for productIdentifier: String) -> String {
        switch productIdentifier {
        case "inc.anky.credits.3":
            return "3 reflections"
        case "inc.anky.credits.11":
            return "11 reflections"
        case "inc.anky.credits.33":
            return "33 reflections"
        default:
            return "credits"
        }
    }

    private static func subtitle(for productIdentifier: String, fallback: String) -> String {
        switch productIdentifier {
        case "inc.anky.credits.11":
            return "Stay with it"
        case "inc.anky.credits.33":
            return "Daily practice"
        default:
            return fallback
        }
    }
}

private extension Array where Element == RevenueCatCreditPackage {
    func uniquedByProductId() -> [RevenueCatCreditPackage] {
        var seen = Set<String>()
        return filter { package in
            seen.insert(package.id).inserted
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
