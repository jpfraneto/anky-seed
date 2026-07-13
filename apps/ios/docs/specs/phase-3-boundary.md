# Subscription boundary — production source map

Revised July 11, 2026. Runtime code and tests control when this note differs.

## Product configuration

- iOS monthly product: `anky.monthly` (`P1M`, no introductory offer)
- iOS annual product: `anky.annual` (`P1Y`; Apple may show a three-day trial to an eligible new subscriber)
- RevenueCat entitlement: `pro`
- RevenueCat offering: `default`
- Both durations unlock the same feature set. Billing duration never selects features.
- Android has its own platform product configuration. Do not infer iOS identifiers from Android identifiers.

`AnkyPurchasesConfig`, `SubscriptionCatalogPolicy`, and `EntitlementStore` are the client configuration source. `backend/subscription/routes.ts` and the RevenueCat webhook state in `backend/level/db.ts` are the server source.

## Free and Pro behavior

| Capability | Free | Verified `pro` |
| --- | --- | --- |
| Start, continue, save, browse, copy, export, import, or delete local writing | Yes | Yes |
| Read a saved reflection | Yes | Yes |
| New server-generated reflection | No | Yes, subject to service limits |
| Writing nudge | Local fallback | Server-generated, subject to service limits |
| Screen Time gate and protected-app selection | Yes | Yes |
| Three daily Quick Passes | Yes | Yes |
| Emergency access | Yes | Yes |
| Automatic rest-of-day unlock at the daily target | No | Yes |
| Adaptive target suggestions | No | Yes |
| 96-day journey | No | Yes |
| Static painting progression through level 8 | Yes | Yes |
| Previously delivered personalized paintings | Yes | Yes |
| Personalized progression after level 8 | No | Yes, subject to progress and generation limits |
| Archive, history, settings, backup, support, legal, deletion | Yes | Yes |

The server rejects new reflection, nudge, and level-9-or-later generation requests when account entitlement is inactive. Static levels 1–8 are shared defaults. Delivered local writing, saved reflections, and paintings are not deleted on lapse.

## Verified entitlement lifecycle

`EntitlementStore.verificationState` is the only client-side Pro gate. A cached entitlement exists only for harmless visual continuity and cannot create paid local state.

At launch and each activation:

1. `WriteBeforeScrollSpikeViewModel.reconcileOnAppActive(hasCurrentVerifiedPro: false)` removes a writing-sourced daily grant before a network refresh.
2. RevenueCat is identified with the pseudonymous writer/account identifier.
3. `EntitlementStore.reconcileOnForeground()` fetches current `CustomerInfo`.
4. Only `.verifiedActive` can grant the automatic rest-of-day unlock, server nudges, journey access, or personalized progression.
5. Inactive or failed refreshes remain closed. Quick Pass and emergency grants are not revoked.

Purchase and restore immediately apply returned `CustomerInfo`, require active lowercase `pro`, and identify current entitlement to the backend. A completed transaction without `pro` produces an actionable error instead of advancing onboarding.

Promotional or open-ended RevenueCat access counts when current `CustomerInfo` marks `pro` active.

## Trial presentation

The annual trial is presented only when all of these are true:

- the package is exactly `anky.annual` with a one-year period;
- its real StoreKit discount is a three-day free trial; and
- RevenueCat returns positive introductory-offer eligibility.

Loading, missing, unknown, failed, ineligible, or future unsupported eligibility states show normal annual renewal terms. Monthly never displays trial copy under the current configuration.

## Paywall reachability

Fresh install reaches the paywall as the final onboarding step. Purchase and Restore Purchases remain primary actions, while **Continue with free writing** completes onboarding without changing entitlement. That action remains available when products or offerings fail to load.

Later, the paywall is reachable from painting/home **Settings** → the top **Subscription** card and from actual Pro veils. The paywall uses StoreKit/RevenueCat localized price data and has external links to `https://anky.app/privacy-policy` and Apple's standard EULA.

## Tests and release invariants

- `SubscriptionRemediationTests.swift` covers identifiers, periods, trial fail-closed policy, free onboarding, transaction resolution, legal controls, localized resource presence, the feature boundary, and stale-entitlement regression policy.
- Swift package tests cover the actual gate, Quick Pass, emergency, level-8 boundary, storage, saved-reflection, and daily-unlock mechanics.
- Backend tests prove entitlement checks happen before generated-service provider calls and level 9 is the first personalized painting gate.
- `EntitlementStore.ignoresEntitlementForQA` and `AppRoot.alwaysShowsOnboardingForQA` must be `false` in Release.
- `Anky.storekit` is a Debug scheme fixture and must not be copied into a Release app or archive.
