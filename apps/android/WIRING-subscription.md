# WS4 wiring — subscription entitlements (`core/subscription`)

New package: `app/src/main/java/inc/anky/android/core/subscription/`. Nothing
outside it was touched; this file is the contract for the phases that wire it
in and delete the credits economy.

## Files

| Android | Ported from (iOS) |
|---|---|
| `AnkyPurchasesConfig.kt` (`AnkyPurchasesConfig` + `AnkyPurchases`) | `Anky/Purchases/AnkyPurchasesConfig.swift` |
| `SubscriptionModels.kt` (snapshot/package models, `SubscriptionBackend`, `SubscriptionGateway`) | derived from `EntitlementStore.swift` types |
| `EntitlementStore.kt` (`EntitlementState`, `EntitlementStore`) | `Anky/Purchases/EntitlementStore.swift` |
| `RevenueCatSubscriptionGateway.kt` | the SDK-facing half of `EntitlementStore.swift` |
| `PurchaseConstants.kt` (`SubscriptionPriceFormatter`, `PaywallPressureLedger`) | `Anky/Purchases/PurchaseConstants.swift` |
| `TrialReminder.kt` (`TrialReminderContract/Planner/Port/Sync`) | `LocalNotificationScheduler.swift` (trial parts) + `EntitlementStore.syncTrialReminder` |
| `EntitlementGates.kt` | every `isEntitledForGating` gate site (inventory in its KDoc) |

Tests: `app/src/test/java/inc/anky/android/subscription/` —
`SubscriptionPriceFormatterTest`, `PaywallPressureLedgerTest`,
`TrialReminderTest`, `EntitlementStoreTest`, plus `SubscriptionTestSupport`
(fake prefs / gateway / backend / reminder port).

## Wiring (later phase)

1. **AppContainer**
   ```kotlin
   val subscriptionPrefs = appContext.getSharedPreferences("anky-subscription", Context.MODE_PRIVATE)
   val subscriptionGateway = RevenueCatSubscriptionGateway(appContext) { identityStore.loadOrCreate().address }
   val entitlementStore = EntitlementStore(
       gateway = subscriptionGateway,
       backend = /* adapter over LevelSyncClient (WS3): identify -> POST /subscription/identify, funnel -> POST /events/funnel */,
       preferences = subscriptionPrefs,
       scope = /* app-scope CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate) */,
       trialReminder = TrialReminderSync(/* AlarmManager TrialReminderPort, notifications workstream */),
   )
   ```
   `SubscriptionBackend` is deliberately minimal so this package never imports
   `core/level`; the adapter lives at the container.
2. **Launch** (app root, once identity is loaded — never lazily):
   `AnkyPurchases.identifyCurrentWriter(context, identity.address)` then
   `entitlementStore.start()`. Fail closed: null identity leaves the SDK
   unconfigured; `ensureConfigured()` retries at point of use (purchase /
   restore / loadPackages all call it).
3. **Foreground** (ON_RESUME / ProcessLifecycleOwner):
   `identifyCurrentWriter` → `start()` → `reconcileOnForeground()` (fresh
   customer info; cancels the trial reminder if the trial was cancelled in
   Play settings; deduped backend identify).
4. **Entitlement change** (collect `entitlementStore.state`): push
   `isEntitledForGating` into the level coordinator (`entitledForGating`),
   the write/unlock policy (`dailyUnlockEntitled`), and the widget sync —
   the gate inventory is in `EntitlementGates`' KDoc with iOS file:line.
5. **Purchase** needs a foreground `Activity` (Play Billing):
   `entitlementStore.purchase(pkg, activity)` — it awaits the backend
   identify before returning (race-safe pay → confirm → generate).
6. **Trial reminder platform impl** (notifications workstream): implement
   `TrialReminderPort` with AlarmManager (needs `SCHEDULE_EXACT_ALARM` or
   WorkManager fallback) + `POST_NOTIFICATIONS`; use
   `TrialReminderContract.REMINDER_ID/TITLE/BODY`. Re-run
   `entitlementStore.reconcileOnForeground()` after notification permission
   is granted (paywall comes one screen before the ask, like iOS).
7. **Paywall UI** (later phase): `PaywallView` port consumes
   `entitlementStore.state`, `SubscriptionPriceFormatter.price/weekly`
   (fallbacks "$88", "$11.99", "$1.69/wk"), `yearlyTrialEligibility()`, and
   records `PaywallPressureLedger.recordPaywallShown(subscriptionPrefs)` on
   appear (plus `paywall_shown {origin}` funnel). Ambient surfaces must check
   `PaywallPressureLedger.isWithinQuietWindow` first.

## Play Console / RevenueCat dashboard prerequisites

- Play Console must define **subscriptions with product ids `anky.yearly`
  ($88/yr, 3-day free-trial offer on the base plan) and `anky.monthly`
  ($11.99/mo, no trial)** — same ids as iOS so the RevenueCat `pro`
  entitlement and `default` offering map cross-platform. RC Android product
  ids arrive as `productId:basePlanId`; the gateway strips the suffix.
- RevenueCat dashboard: attach both Play products to entitlement `pro` and
  offering `default`. The Android public key is already plumbed as
  `BuildConfig.REVENUECAT_ANDROID_PUBLIC_KEY` (from
  `ANKY_REVENUECAT_ANDROID_PUBLIC_KEY`).
- Trial eligibility on Android = Play returns a `freeTrial` subscription
  option (Play pre-filters by eligibility); there is no
  `checkTrialOrIntroDiscountEligibility` equivalent.

## Coexistence warning (until credits die)

`RevenueCatCreditsClient.configure` and `AnkyPurchases.identifyCurrentWriter`
both configure the singleton `Purchases` SDK. Both use the same appUserID
(wallet address), so order is harmless, but **only one owner must remain**:
when credits are deleted, `AnkyPurchases` becomes the sole configurer. Until
then, configure `AnkyPurchases` first at launch.

## Credits-economy deletion checklist (cleanup phase)

Everything below must die or be rewritten. Grep basis: `credit|Credit|CRD|onramp|Token|x402`.

**Delete outright**
- `app/src/main/java/inc/anky/android/core/credits/RevenueCatCreditsClient.kt`
  (whole file: `CreditsClient`, `RevenueCatCreditsClient`, `CreditCatalog`
  with `CRD` currency, `Credits` offering, `inc.anky.credits.3/11/33`).
- `app/src/main/java/inc/anky/android/core/credits/ReflectionCreditCache.kt`
  (`ReflectionCreditCache`, `NoopReflectionCreditCache`,
  `SharedPreferencesReflectionCreditCache`; prefs files
  `anky-reflection-credit-cache`, `anky-credit-prompt` — add a one-time
  cleanup that deletes these prefs).
- `app/src/test/java/inc/anky/android/credits/CreditCatalogTest.kt`.
- `ReflectionCreditPromptState` / `ReflectionCreditPresentation` in
  `app/src/main/java/inc/anky/android/core/mirror/MirrorEligibility.kt`.

**Rewire (references to remove/replace)**
- `app/src/main/java/inc/anky/android/app/AppContainer.kt`: `creditsClient`,
  `reflectionCreditCache` + their four imports → replace with
  `entitlementStore` wiring above.
- `app/src/main/java/inc/anky/android/app/AnkyNav.kt:16`: `AnkyRoute.YouCredits`
  ("you/credits") route.
- `app/src/main/java/inc/anky/android/app/AnkyApp.kt`: ~27 references —
  `YouCredits` composable/route/icon/selected-state (lines ~470-493, 701,
  716, 723), `creditsClient`/`reflectionCreditCache` plumbing into You and
  Reveal (lines ~431, 477, 544-562), `onOpenCredits`.
- `app/src/main/java/inc/anky/android/feature/you/YouScreen.kt` (~232 refs)
  and `YouViewModel.kt` (~170 refs): the whole Credits page — balance,
  credit packs, purchase/restore of credit packs, free-credit WhatsApp claim
  flow, `YouInitialPage.Credits`. Restore-purchases moves to the
  subscription store (`EntitlementStore.restore()`), keeping the
  user-triggered-only invariant.
- `app/src/main/java/inc/anky/android/feature/reveal/RevealScreen.kt`
  (~199 refs) and `RevealViewModel.kt` (~193 refs): credit CTA states,
  credit-prompt sheets, `hasClaimedFreeCreditsProvider` /
  `markFreeCreditsClaimed` → replaced by the reflection veil
  (`EntitlementGates.freeSessionSkipsLlmReflection`) + paywall sheet.
- `app/src/main/java/inc/anky/android/core/mirror/MirrorClient.kt`:
  `X-Anky-Credits-Remaining` header parsing (lines 70, 188, 222) and
  `"INSUFFICIENT_CREDITS"` → `MirrorErrorCode.InsufficientCredits` (line 213)
  → replace with 402 `ENTITLEMENT_REQUIRED` → veil (PARITY WS4).
- `app/src/main/java/inc/anky/android/core/mirror/MirrorModels.kt`:
  `creditsRemaining` field (line 8), `MirrorErrorCode.InsufficientCredits`
  (line 31).
- `app/src/main/java/inc/anky/android/feature/write/WriteViewModel.kt:547`:
  nudge error mapping "that nudge needs one credit." → free writers now get
  the local fallback nudge via `EntitlementStore.lastKnownEntitledForGating`
  (iOS WriteViewModel.swift:529).
- Storage: `creditsRemaining` on `SavedReflection`
  (`core/storage/StorageModels.kt:37`, `ReflectionStore.kt:68/77`,
  `Exporter.kt:113`, `BackupImporter.kt:155/188-198`) — keep READ tolerance
  for old backups (import must not break), stop writing it.
- `app/src/main/java/inc/anky/android/core/privacy/PrivacyMessages.kt`: one
  credit mention in legal copy → subscription-reality text (WS8).

**String resources** (all six locales: `values`, `values-es`, `values-fr`,
`values-de`, `values-hi`, `values-zh-rCN`)
- `strings.xml`: ~42-48 credit strings per locale (`you_credits`, `credit`,
  `credits`, `credit_rule_*`, `refresh_credits`, `credit_pack_*`,
  `you_status_*credit*`, `you_credit_*`, `write_nudge_credit_error`,
  `you_conversation_checking_credit_gate`, credit mentions inside
  `you_recovery_replaces_access`, `you_delete_account_data_detail_body`,
  `reset_identity_warning`, `you_restore_identity_note`, ...).
- `article_strings.xml`: credit mentions in en/de/hi/zh article copy (~17 in
  en and de).
- Update `LocalizationResourceTest` counts when removing (WS9).

**Tests referencing credits** (delete or rewrite alongside):
- `app/src/test/java/inc/anky/android/credits/CreditCatalogTest.kt`
- credit assertions in `feature/you/YouViewModelStateTest.kt`,
  `feature/reveal/RevealViewModelTest.kt`, `write/WriteViewModelTest.kt`,
  `mirror/MirrorClientTest.kt`, `storage/StorageTest.kt`.
- `app/src/test/java/inc/anky/android/privacy/SourceInvariantTest.kt`: the
  `networkAndPurchaseClientsStayInExplicitPaths` allowlist pins
  `Purchases*` tokens to the credits client, and
  `revenueCatRestoreIsUserTriggeredAndDoesNotProgrammaticallySyncPurchases` /
  `revenueCatAndroidFallsBackToDirectCreditProductsLikeIos` assert on credits
  files. NOTE: this test currently resolves paths under `apps/android/...`
  and `apps/ios/...`, which no longer exist (the app moved to
  `apps/android`), so the whole suite is stale — when it is
  revived, the allowlist must include
  `core/subscription/RevenueCatSubscriptionGateway.kt` and
  `core/subscription/AnkyPurchasesConfig.kt`.

**Not present on Android (nothing to delete):** TokenPage/$ANKY onramp
(`StripeOnrampClient`) and x402 progress stages never shipped in this Android
app; only the mirror credit headers above remain. `Token` grep hits are
BIP39/IME token vocabulary — keep.

**Keep (not credits-economy):** `core/level/LevelProgressStore.kt`
"credit(s)" = time-crediting of sealed sessions (WS3);
`identity/BIP39WordList.kt`; `HiddenTextInput.kt` token comment.
