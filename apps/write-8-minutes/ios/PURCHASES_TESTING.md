# Testing purchases (RevenueCat + local StoreKit configuration)

The products (`anky.yearly`, `anky.monthly`) do not exist in App Store
Connect yet — every purchase test runs against the local StoreKit
configuration file `Anky.storekit`, which is already attached to the Anky
scheme (Edit Scheme… → Run → Options → StoreKit Configuration).

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

- Fetching the `default` offering and its yearly/monthly packages
  (packages must be configured in the RevenueCat dashboard first).
- Purchasing either plan; `EntitlementStore.isEntitledForGating` flips
  once RevenueCat validates and the `pro` entitlement activates.
- The yearly 3-day free trial (intro offer) and `periodType == .trial`.
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

## Ship-time checklist (once App Store Connect products exist)

1. Scheme → Run → Options → **StoreKit Configuration → None** (purchases
   then go through the real sandbox/App Store).
2. Nothing else changes in code — products, entitlement (`pro`), and
   offering (`default`) identifiers are already production values in
   `AnkyPurchasesConfig`.
