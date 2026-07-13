# WIRING — paywall (feature/paywall)

New package: `app/src/main/java/inc/anky/android/feature/paywall/`, plus
`res/values/strings_paywall.xml` and tests under
`app/src/test/java/inc/anky/android/paywall/`. Nothing outside those paths was
touched; this file is the contract for the shell that wires it in.

## Files

| Android | Ported from (iOS) |
|---|---|
| `PaywallContext.kt` (`PaywallContext`, `PaywallFunnel`) | `PaywallView.Context` + funnel tags |
| `PaywallModels.kt` (`PaywallCopy`, `PaywallLine`/`PaywallArg`, `PaywallPlan`, `PaywallTimelineNode`, `PaywallPlanSelection`) | the computed copy properties of `PaywallView.swift`, made pure |
| `PaywallScreen.kt` (`PaywallScreen`, `PaywallDefaults.PAYWALL_IS_SKIPPABLE`, `resolve`, `findActivity`) | `PaywallView` body/actions |
| `PaywallSheet.kt` | `PaywallSheet` (veil/boundary presentation) |
| `FreeTargetMomentCard.kt` (+ `FREE_TARGET_MOMENT_ORIGIN`) | `freeTargetMomentBlock` in `AppRoot.swift` |
| `strings_paywall.xml` | all paywall copy; Play wording where iOS says App Store |

## Integration signatures

```kotlin
PaywallScreen(
    store = entitlementStore,
    context = PaywallContext.Onboarding /* or .Lapsed, or .Veil(origin) */,
    onCompleted = { /* advance onboarding / pop */ },
    onShowTerms = { /* present terms sheet (WS8) */ },
    onShowPrivacy = { /* present privacy sheet (WS8) */ },
    onFunnelEvent = { event, origin -> funnelAdapter.report(event, origin) },
    subscriptionPreferences = appContainer.subscriptionPrefs, // "anky-subscription"
)

PaywallSheet(
    store = entitlementStore,
    origin = "reflection" /* "ceremony", "journey", "widget", "quick_action" */,
    onDismiss = { showsPaywall = false },
    onShowTerms = ..., onShowPrivacy = ...,
    onFunnelEvent = ..., subscriptionPreferences = ...,
)

FreeTargetMomentCard(
    store = entitlementStore,
    onDismiss = { /* "not now" → back to the gate */ },
    onShowTerms = ..., onShowPrivacy = ...,
    onFunnelEvent = ..., subscriptionPreferences = ...,
    onEmergency = { /* non-null keeps the emergency-breath link visible */ },
)
```

Host `PaywallScreen` over `LazureWall(LazureMood.Dawn)` inside `LazureTheme`
(onboarding screen 10 / lapsed root do this; `PaywallSheet` paints its own
dawn wall). The screen is one Column — give it horizontal padding ~30dp and
`widthIn(max = 620.dp)` in a scroll container, like the sheet does.

## Contract notes

- **Activity requirement.** Play Billing purchases need a foreground
  `Activity`. `PaywallScreen` unwraps it from `LocalContext` via a
  ContextWrapper walk (`findActivity()`), so it must be composed inside an
  Activity's content — never a Service/appContext-hosted composition. A null
  activity reaches `EntitlementStore.purchase(pkg, null)`, which fails with
  the quiet error line rather than crashing.
- **Funnel + pressure ledger.** `paywall_shown {origin}` fires through
  `onFunnelEvent` on the screen's first composition when not entitled (iOS
  `onAppear`); `PaywallSheet` delegates to the hosted screen, so callers never
  report it themselves. When `subscriptionPreferences` is passed, the screen
  also records `PaywallPressureLedger.recordPaywallShown` — pass the
  `anky-subscription` prefs file. `trial_started` / `subscribed` fire with the
  same origin after a successful purchase. Ambient (Anky-initiated) surfaces
  must check `PaywallPressureLedger.isWithinQuietWindow` before presenting.
- **Context = copy only.** `PaywallContext` switches words, never styling —
  deliberate (iOS canon) so the variants cannot drift apart visually. All
  copy mapping lives in `PaywallCopy` (pure, JVM-tested).
- **Skippable flag.** `PaywallDefaults.PAYWALL_IS_SKIPPABLE` (false) is the
  QA/Play-review escape hatch: true shows a quiet "later" link that calls
  `onCompleted` without purchase. MUST be false in shipped builds — pinned by
  `PaywallPlanSelectionTest.paywallMustNotBeSkippableInShippedBuilds`.
- **Onboarding has no dismiss.** With the flag false there is no way past the
  onboarding paywall except purchase/restore; Lapsed/Veil hosts own their
  dismissal (the sheet's swipe/scrim calls `onDismiss`).
- **"Have a code?" omitted.** iOS presents StoreKit's offer-code redemption
  sheet; Play Billing has no in-app equivalent (codes redeem in the Play
  Store app). If ever needed: deep-link `https://play.google.com/redeem`.
- **Entitled state.** The screen renders honestly while entitled (title/voice/
  payment line become status; CTA becomes "Done" → `onCompleted`), so it is
  safe to reach with an active subscription.
- **Free-target-moment copy** stays in `core/copy/AnkyCopyRegistry` (like
  iOS); the card reads it there. The card owns its own `PaywallSheet`
  presentation with origin `free_target_moment`. Once-per-day gating +
  free-writer eligibility are the host's job (iOS: `UnlockPolicy`'s
  `anky.freeTargetMoment.lastShownDay`).
- **Localization (WS9).** `strings_paywall.xml` is `translatable="false"`
  until the six locales land; update `LocalizationResourceTest` counts then.

## Tests

`app/src/test/java/inc/anky/android/paywall/` — `PaywallCopyMappingTest`
(context→copy table, timeline model), `PaywallCopyPricingTest` (payment/CTA/
plan-card lines over real micros; fallbacks $88 / $11.99 / $1.69),
`PaywallPlanSelectionTest` (yearly preselected, same-plan no-op, skippable
pin, funnel names). Pure JVM, no Robolectric:

```
./gradlew :app:testDebugUnitTest --tests "inc.anky.android.paywall.*"
```
