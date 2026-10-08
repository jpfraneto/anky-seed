import XCTest
@testable import Anky

@MainActor
final class SubscriptionRemediationTests: XCTestCase {
    private var iosRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testCanonicalIOSPurchaseConfiguration() {
        XCTAssertEqual(AnkyPurchasesConfig.annualProductID, "anky.annual")
        XCTAssertEqual(AnkyPurchasesConfig.monthlyProductID, "anky.monthly")
        XCTAssertEqual(AnkyPurchasesConfig.purchasableProductIDs, ["anky.annual", "anky.monthly"])
        // Historical weekly identifiers stay recognizable for receipts/status,
        // but are deliberately absent from the purchasable catalog.
        XCTAssertEqual(AnkyPurchasesConfig.weeklyProductID, "anky.weekly")
        XCTAssertEqual(AnkyPurchasesConfig.entitlementID, "pro")
        XCTAssertEqual(AnkyPurchasesConfig.offeringID, "default")
        XCTAssertEqual(AnkySubscriptionPlan.allCases, [.annual, .monthly])
        XCTAssertEqual(AnkySubscriptionPlan.annual.entitlementID, "pro")
        XCTAssertEqual(AnkySubscriptionPlan.annual.expectedPeriod.value, 1)
        XCTAssertEqual(AnkySubscriptionPlan.annual.expectedPeriod.unit, .year)
        XCTAssertEqual(AnkySubscriptionPlan.monthly.entitlementID, "pro")
        XCTAssertEqual(AnkySubscriptionPlan.monthly.expectedPeriod.value, 1)
        XCTAssertEqual(AnkySubscriptionPlan.monthly.expectedPeriod.unit, .month)
    }

    func testReleaseInspectablePurchaseMetadataMatchesRuntimeConstants() throws {
        let infoURL = iosRoot.appendingPathComponent("Anky/Info.plist")
        let data = try Data(contentsOf: infoURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        )
        let config = try XCTUnwrap(plist["AnkyRevenueCatConfiguration"] as? [String: String])
        XCTAssertEqual(Set(config.keys), ["AnnualProduct", "MonthlyProduct", "Entitlement", "Offering"])
        XCTAssertEqual(config["AnnualProduct"], AnkyPurchasesConfig.annualProductID)
        XCTAssertEqual(config["MonthlyProduct"], AnkyPurchasesConfig.monthlyProductID)
        XCTAssertEqual(config["Entitlement"], AnkyPurchasesConfig.entitlementID)
        XCTAssertEqual(config["Offering"], AnkyPurchasesConfig.offeringID)
    }

    func testAnnualAndMonthlyCatalogIgnoresLegacyAndUnknownProducts() {
        XCTAssertEqual(
            SubscriptionCatalogPolicy.discoveredPlans(
                productIDs: ["anky.weekly", "anky.monthly", "anky.annual"]
            ),
            [.annual, .monthly]
        )
        XCTAssertEqual(
            SubscriptionCatalogPolicy.discoveredPlans(productIDs: ["anky.yearly"]),
            []
        )
        XCTAssertFalse(SubscriptionCatalogPolicy.containsRequiredPlans(productIDs: ["anky.monthly"]))
        XCTAssertTrue(SubscriptionCatalogPolicy.containsRequiredPlans(
            productIDs: ["anky.weekly", "anky.monthly", "anky.annual"]
        ))
        XCTAssertFalse(SubscriptionCatalogPolicy.containsRequiredPlans(productIDs: ["anky.annual"]))
    }

    func testTrialCopyIsNeverDisplayed() {
        // The free trial is disabled (user decision, 2026-07-24): no state
        // may advertise trial copy, not even a store-confirmed eligible one.
        XCTAssertFalse(AnnualTrialEligibilityState.eligible.displaysTrial)
        XCTAssertFalse(AnnualTrialEligibilityState.ineligible.displaysTrial)
        XCTAssertFalse(AnnualTrialEligibilityState.unknown.displaysTrial)
        XCTAssertFalse(AnnualTrialEligibilityState.failed.displaysTrial)
        XCTAssertFalse(AnnualTrialEligibilityState.loading.displaysTrial)
        XCTAssertFalse(AnnualTrialEligibilityState.noOffer.displaysTrial)
        XCTAssertFalse(AnnualTrialEligibilityState.unsupported.displaysTrial)
    }

    func testTrialLookupFailureAndUnknownFutureCaseFailClosed() {
        XCTAssertEqual(AnnualTrialEligibilityState.fromRevenueCat(nil), .failed)
        // `.unsupported` is the app's explicit result for RevenueCat's
        // `@unknown default` path and must never authorize trial copy.
        XCTAssertFalse(AnnualTrialEligibilityState.unsupported.displaysTrial)
    }

    func testLocalizedStorePriceIsPreservedAndThereIsNoFallback() {
        XCTAssertEqual(
            SubscriptionPriceFormatter.price(localizedStorePrice: "12,99 €"),
            "12,99 €"
        )
        XCTAssertEqual(
            SubscriptionPriceFormatter.price(localizedStorePrice: " ₹999 "),
            "₹999"
        )
        XCTAssertNil(SubscriptionPriceFormatter.price(localizedStorePrice: nil))
        XCTAssertNil(SubscriptionPriceFormatter.price(localizedStorePrice: "   "))
    }

    func testFreshOnboardingCanPurchaseRestoreOrContinueFree() {
        XCTAssertTrue(OnboardingSubscriptionPolicy.shouldAdvance(after: .purchaseActivated))
        XCTAssertTrue(OnboardingSubscriptionPolicy.shouldAdvance(after: .restoreActivated))
        XCTAssertTrue(OnboardingSubscriptionPolicy.shouldAdvance(after: .continueFree))
        XCTAssertFalse(OnboardingSubscriptionPolicy.shouldAdvance(after: .purchaseCancelled))
        XCTAssertFalse(OnboardingSubscriptionPolicy.shouldAdvance(after: .purchaseFailed))
        XCTAssertFalse(OnboardingSubscriptionPolicy.shouldAdvance(after: .restoreWithoutEntitlement))
        XCTAssertFalse(OnboardingSubscriptionPolicy.shouldAdvance(after: .productsUnavailable))
    }

    func testFreeContinuationSurvivesLoadingAndUnavailableProducts() {
        XCTAssertTrue(OnboardingSubscriptionPolicy.allowsFreeContinuation(while: .loading))
        XCTAssertTrue(OnboardingSubscriptionPolicy.allowsFreeContinuation(while: .available))
        XCTAssertTrue(OnboardingSubscriptionPolicy.allowsFreeContinuation(while: .unavailable))
    }

    func testPurchaseAndRestoreRequireLowercasePro() {
        XCTAssertEqual(
            SubscriptionTransactionPolicy.purchaseSucceeded(
                userCancelled: false,
                activeEntitlementIDs: ["pro"]
            ),
            .activated
        )
        XCTAssertEqual(
            SubscriptionTransactionPolicy.purchaseSucceeded(
                userCancelled: true,
                activeEntitlementIDs: ["pro"]
            ),
            .cancelled
        )
        XCTAssertEqual(
            SubscriptionTransactionPolicy.purchaseSucceeded(
                userCancelled: false,
                activeEntitlementIDs: []
            ),
            .missingProEntitlement
        )
        XCTAssertEqual(
            SubscriptionTransactionPolicy.restoreSucceeded(activeEntitlementIDs: ["pro"]),
            .activated
        )
        XCTAssertEqual(
            SubscriptionTransactionPolicy.restoreSucceeded(activeEntitlementIDs: []),
            .nothingToRestore
        )
    }

    func testFreeAndProFeatureBoundary() {
        let freeFeatures: [AnkyFeature] = [
            .writing, .localWritingNudge, .existingReflection, .gate,
            .quickPass, .emergencyUnlock, .staticPaintingLevelsOneThroughEight,
            .deliveredPersonalizedPainting, .archiveAndHistory, .backupAndSettings,
            .serverWritingNudge, .journey,
            .automaticDailyTargetUnlock, .adaptiveTargetSuggestions,
            .personalizedPaintingAfterLevelEight,
        ]
        let proFeatures: [AnkyFeature] = [.betterAIReflection]
        for feature in freeFeatures {
            XCTAssertFalse(AnkyFeatureAccessPolicy.requiresPro(feature), "\(feature)")
        }
        for feature in proFeatures {
            XCTAssertTrue(AnkyFeatureAccessPolicy.requiresPro(feature), "\(feature)")
        }
        XCTAssertEqual(Set(freeFeatures + proFeatures).count, AnkyFeature.allCases.count)
    }

    func testDailyUnlockDoesNotDependOnPro() {
        XCTAssertFalse(PaidDailyUnlockReconciliationPolicy.shouldRevoke(
            tierRawValue: "daily",
            sourceRawValue: "writing",
            hasCurrentVerifiedPro: false
        ))
        XCTAssertTrue(PaidDailyUnlockReconciliationPolicy.canCreate(
            hasCurrentVerifiedPro: false
        ))
        XCTAssertTrue(PaidDailyUnlockReconciliationPolicy.canCreate(
            hasCurrentVerifiedPro: true
        ))
    }

    func testPaywallUsesFunctionalPublicLegalControls() {
        XCTAssertEqual(
            SubscriptionLegalLinks.privacyPolicyURL.absoluteString,
            "https://anky.app/privacy-policy/"
        )
        XCTAssertEqual(
            SubscriptionLegalLinks.termsOfUseURL.absoluteString,
            "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
        )
        let source = try! String(
            contentsOf: iosRoot.appendingPathComponent("Anky/Purchases/PaywallView.swift"),
            encoding: .utf8
        )
        for identifier in [
            "paywall.purchase", "paywall.restore", "paywall.continueFree",
            "paywall.privacy", "paywall.terms",
        ] {
            XCTAssertTrue(source.contains(identifier), identifier)
        }
        XCTAssertTrue(source.contains("\"Better reflections from Anky's strongest available model\""))
        XCTAssertFalse(source.contains("96-day writing journey"))
        XCTAssertFalse(source.contains("Automatic rest-of-day unlock"))
    }

    func testAllSixLocalizedAppAndBundledLegalResourcesExist() {
        let locales = ["en", "es", "fr", "de", "zh-Hans", "hi"]
        for locale in locales {
            let directory = iosRoot.appendingPathComponent("Anky/\(locale).lproj")
            for resource in [
                "Localizable.strings", "PrivacyPolicy.md", "TermsAndConditions.md",
            ] {
                XCTAssertTrue(
                    FileManager.default.fileExists(
                        atPath: directory.appendingPathComponent(resource).path
                    ),
                    "Missing \(locale)/\(resource)"
                )
            }
        }
    }

    func testStoreKitDebugConfigurationHasCanonicalDurationsAndNoTrials() throws {
        let data = try Data(contentsOf: iosRoot.appendingPathComponent("Anky/Anky.storekit"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let groups = try XCTUnwrap(root["subscriptionGroups"] as? [[String: Any]])
        let subscriptions = try XCTUnwrap(groups.first?["subscriptions"] as? [[String: Any]])
        let byID = Dictionary(uniqueKeysWithValues: subscriptions.compactMap { product -> (String, [String: Any])? in
            guard let id = product["productID"] as? String else { return nil }
            return (id, product)
        })
        XCTAssertEqual(Set(byID.keys), ["anky.monthly", "anky.annual"])
        XCTAssertEqual(byID["anky.monthly"]?["recurringSubscriptionPeriod"] as? String, "P1M")
        XCTAssertEqual(byID["anky.annual"]?["recurringSubscriptionPeriod"] as? String, "P1Y")
        XCTAssertTrue(byID["anky.monthly"]?["introductoryOffer"] is NSNull)
        XCTAssertTrue(byID["anky.annual"]?["introductoryOffer"] is NSNull)
    }
}
