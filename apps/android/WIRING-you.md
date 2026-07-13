# WIRING — You tab rework + AnkySettingsScreen (WS8)

## What changed

- `feature/you/YouScreen.kt`: reworked to the current iOS home — lazure wall
  (`LazureWall(Dawn)`), header (AvatarStore selfie or `you_avatar_anky`,
  writer name from `WritingAnchorStore`, accountId), stats row (ankys /
  minutes / streak → History), menu rows: Settings entry, Data toggle
  (→ Export page), Write Before You Scroll (→ `onGateSetupRequested`), daily
  target stepper (`DailyTargetStore.requestTargetChange` + `target_changed`
  event, next-day note), Account, Support prompt, Privacy, Terms,
  Subscription (EntitlementState status → Subscription page), founder chat
  (https://t.me/ankytheapp), device-lock toggle, app version. Delete-account
  flow unchanged (hidden panel behind the "!" toggle + confirm dialog).
- `feature/you/YouViewModel.kt`: `YouState.subscription: EntitlementState` +
  `isSubscriptionTruthAvailable`; optional ctor param
  `entitlementStore: EntitlementStore? = null`; `restorePurchases()` now =
  `EntitlementStore.restore()` (surfaces `restoreStatusLine`);
  `recoveryImportErrorMessage` maps the BIP-39 checksum throw
  ("Recovery phrase checksum is invalid.") to the iOS copy. Subscription
  presentation helpers (`subscriptionStatusTitle/Detail`, price lines,
  `PlayManageSubscriptionsUrl`, `FounderChatUrl`) are internal + unit-tested.
- NEW `feature/settings/AnkySettingsScreen.kt`: port of AnkySettingsView —
  subscription section, daily-target slider (next-day note), writer name,
  backspace/autocorrect toggles, font ×5 / size ×4 chips + live preview,
  protection (encrypted backup, app lock, blocked-apps entry, gate-off
  state line), paintings disclosure, mirror URL override, support, legal
  (reuses You `PrivacyPage`/`TermsPage`), danger zone (clear-data → You
  dialog), about/version. Self-contained: writing prefs / daily target /
  anchor / gate switch read context-backed stores; app-level state arrives
  as params. Rendered inside YouScreen as `YouPage.Settings` (full-bleed).

## Deleted vs deprecated (credits/token)

- DELETED from UI/VM: CreditsPage, YouReflectionCreditsSheet, credit
  package rows/buttons, TokenPage, $ANKY home row, `purchaseCredits`,
  `StripeOnrampClient` + `createAnkyOnrampUrl` + `isOpeningAnkyOnramp`
  (AnkyApp does not reference them — checked), `freeCreditWhatsAppUrl`,
  OkHttp import in YouViewModel, `token_article_body` (all 6 locales).
- DEPRECATED stubs kept compiling (cleanup phase deletes): `YouState`
  credit fields/computed props (`creditState`, `hasClaimedFreeCredits`,
  `purchasingCreditPackageId`, `presentedCreditBalance`, `creditDetailTitle`
  …), `refreshCredits()` (unreachable from UI), `creditsClient` /
  `reflectionCreditCache` ctor params + the RevenueCat logout inside
  `deleteAccountAndDataEverywhere`, `afterDeviceGiftDenialGate`,
  `creditLoadFailureState`, `freeCreditMessage`. These exist ONLY because
  (a) AnkyApp.kt still constructs YouViewModel with them, (b) the legacy
  `feature/you/YouViewModelStateTest.kt` and non-WS8 SourceInvariantTest
  methods still pin them. Delete together per WIRING-subscription.md.
- `YouInitialPage.Credits` kept (AnkyApp/AnkyNav reference it); it now lands
  on the Subscription page. `AnkyRoute.YouCredits` left in AnkyNav for the
  integrator.

## Integrator TODOs

1. Pass the container's `EntitlementStore` into both `YouViewModel(...)`
   call sites in AnkyApp.kt (`entitlementStore = container.entitlementStore`)
   once WS4 lands it in AppContainer. Until then the subscription row shows
   "Free / Plans are loading" and restore reports
   `YouStatusCopy.SubscriptionTruthUnavailable`.
2. Pass `onGateSetupRequested = { … }` into `YouScreen(...)` (new optional
   param, default no-op) to open the gate setup flow from the WBS row and
   the settings protection section.
3. When removing `AnkyRoute.YouCredits`, also drop `YouInitialPage` +
   `initialPage`/`onInitialPageBack` params, and Reveal's `onOpenCredits`.
4. `SourceInvariantTest.androidPrivacyPolicyUsesCurrentSupportContactAndAndroidPlatformTerms`
   pins the OLD legal effective date ("June 7, 2026"); the docs are now
   July 6, 2026 (iOS parity), so only that one assertion fails. Bump the
   pinned date in that method (not WS8-owned).
5. `androidTest/.../YouFlowTest.kt` asserts text "identity" on the You home
   — stale against the new home; update when instrumented tests are revived.

## Legal docs

`article_strings.xml` ×6 regenerated from the iOS localized
`PrivacyPolicy.md`/`TermsAndConditions.md` (effective July 6, 2026,
subscription reality) with per-locale Android adaptations: Google Play
purchases/payments/refunds/subscription-settings, encrypted backups +
device secure storage instead of the iOS cloud services, Google account
instead of the Apple identity, "Google Play Terms" section, plus the
Android attestation paragraph and the Google third-party bullet carried
over verbatim from the previous Android translations (they are pinned by
the privacy invariant). Straight apostrophes are emitted as U+2019 —
AAPT2 rejects unescaped `'` even inside CDATA. Generator (deterministic,
re-runnable): scratchpad `gen_articles.py` of this session; re-porting by
hand is equally fine — keep the pinned English sentences listed in
`androidPrivacyPolicyUsesCurrentSupportContactAndAndroidPlatformTerms`.

## Strings

New keys live in `values/strings_you.xml` and `values/strings_settings.xml`
with `translatable="false"` — the WS9 localization pass owns translating
them ×5 locales and flipping the flag (LocalizationResourceTest enforces
parity only for translatable keys). Old credit/token keys in strings.xml
are now unused by WS8 code; delete them with the WS9/WS10 cleanup.

## Tests

- `test/.../you/YouViewModelStateTest.kt` (new, subscription-era) and
  `test/.../settings/AnkySettingsStateTest.kt` (store round-trips + pure
  derivations) — green.
- Rewrote 3 SourceInvariantTest methods (delete-flow, home rows + legal
  shape, chat-action shape) against the current iOS — green.
- Legacy `feature/you/YouViewModelStateTest.kt` still passes against the
  deprecated stubs; delete it with the credits cleanup.
