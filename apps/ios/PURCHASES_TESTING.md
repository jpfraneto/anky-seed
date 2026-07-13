# Testing purchases (RevenueCat + local StoreKit configuration)

The production identifiers are `anky.annual` and `anky.monthly`. Repository
tests use the local `Anky.storekit` fixture, which is attached only to the
scheme's Debug Run action (Edit Scheme… → Run → Options → StoreKit
Configuration). The repository cannot establish whether the current products
and offers are complete in App Store Connect or RevenueCat; verify both
dashboards before sandbox testing.

RevenueCat is the transaction owner: `Purchases.configure` runs once at
launch (AppRoot → `AnkyPurchases.identifyCurrentWriter()`) with the wallet
address as appUserID. Purchases made in the simulator validate through
RevenueCat as **sandbox** data.

## One-time setup: upload the StoreKit certificate to RevenueCat

RevenueCat can only validate local-StoreKit purchases if it knows the
config file's signing certificate:

1. Open `Anky.storekit` in Xcode.
2. Menu **Editor → Save Public Certificate**.
3. RevenueCat dashboard → project **Anky** → **Project settings → Apple
   → StoreKit testing framework** → upload that certificate.

Without this, simulator purchases fail RevenueCat validation (the SDK
logs a receipt-validation error and entitlement never activates).

## What works locally

- Fetching the `default` offering and its annual/monthly packages
  (packages must be configured in the RevenueCat dashboard first).
- Purchasing either plan; `EntitlementStore.isEntitledForGating` flips
  once RevenueCat validates and the `pro` entitlement activates.
- Annual three-day trial eligibility cases. Runtime trial copy appears only
  when the product contains that offer and RevenueCat positively confirms the
  current Apple account is eligible; unknown/failed/ineligible states show
  normal annual renewal terms. Monthly has no introductory offer.
- Restore Purchases.
- Resetting: Xcode menu **Debug → StoreKit → Manage Transactions…** →
  delete transactions. Also delete the app (or use a fresh simulator) to
  reset RevenueCat's sandbox customer if needed.

## What does NOT flow locally

- **Cancellation / refund / billing-retry lifecycle** — the local
  StoreKit framework doesn't emit these to RevenueCat, so webhook-driven
  server state can't be exercised end-to-end from the simulator. Backend
  webhook behavior is tested with sample payloads (`bun test` in
  ~/anky/backend) and RevenueCat's dashboard "send test event".
- **Offer code redemption** — `presentCodeRedemptionSheet()` presents but
  has nothing to redeem against until the products exist in App Store
  Connect.
- Promotional entitlements — granted from the RevenueCat dashboard by
  wallet address; they arrive via `customerInfoStream` on real
  (sandbox/production) customers, not via the local StoreKit file.

## Ship-time checklist

1. For a real sandbox run, Scheme → Run → Options → **StoreKit
   Configuration → None**. Keep the checked-in fixture for local Debug runs.
2. Confirm the Archive action is Release and has no StoreKit configuration;
   inspect the archive to ensure `Anky.storekit` is absent.
3. Verify products `anky.monthly` and `anky.annual`, entitlement `pro`, and
   offering `default` in the live dashboards. Do not use an Android annual
   identifier for iOS.
