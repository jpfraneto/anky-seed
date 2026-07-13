# WS7 wiring — reveal + archive (subscription era)

Reveal and the map tab's archive moved from the credits era to entitlement
gating and the current iOS design. Everything below is what the integrator
(AnkyApp/AppContainer owner) must wire; nothing in `core/**` was touched.

## What changed

- `feature/reveal/RevealViewModel.kt` — credit gating replaced by
  entitlement gating. `canAskAnky = complete && !hasReflection && entitled`;
  free/unentitled sessions surface `state.reflectionVeiled` and make ZERO
  mirror calls (`EntitlementGates.freeSessionSkipsLlmReflection`). Removed:
  credit balance/packages/purchasing/free-gift/denied states, x402 + credit
  progress stages, trial-already-claimed copy. Kept: SSE streaming, progress
  stages, pending watcher + 120s retry, delete, section-aware copy, tags,
  continue-writing countdown.
- `feature/reveal/RevealScreen.kt` — lazure restyle (LazureWall paper, ink
  text, violet headings, madder delete). Stats header now uses the REAL
  `artifact.inputStats.backspaceCount/enterCount` (WIRING-core §2 item is
  done on the reveal side). The reflection slot shows, in order: saved
  reflection (+ tags), streaming markdown, watercolor-veil wait, the
  subscription veil (`VeiledFeature` + `ReflectionGhost` +
  `AnkyCopyRegistry.veilReflection`), or the error panel.
  `RevealCreditPurchaseSheet` and every credit CTA state are deleted.
- `feature/reveal/TagSessionsScreen.kt` — lazure restyle; refresh-on-resume
  kept (ON_RESUME observer + initial load).
- `feature/map/ArchiveChamberScreen.kt` (new) — port of iOS
  `ArchiveChamberView`: "Your Writings" serif title, ankys/minutes/streak
  totals row, search bar, Today/Yesterday/dated day sections, rows =
  sun glyph + two lines of the writing + time + duration clock. No counts,
  no protocol status words in rows. Search runs over a lowercased
  reconstructed-text cache keyed by hash (`feature/map/ArchiveSearch.kt`),
  built once per load on `Dispatchers.Default`.
- `feature/map/MapScreen.kt` — `MapScreen` is now a thin delegate to
  `ArchiveChamberScreen`. The old trail map body survives verbatim as
  `LegacyTrailMapScreen` (private, `@Deprecated`) ONLY because ~7 other
  SourceInvariantTest methods still grep its tokens; delete it together
  with those invariants. `MapAllAnkysScreen` is untouched and still routed.
- `feature/map/MapViewModel.kt` — unchanged refresh; gained
  `archiveEntries: StateFlow<List<SavedAnky>>` + `refreshArchiveEntries()`
  (archive list loaded on an injectable dispatcher, default IO).
- New string files: `res/values/strings_reveal.xml`,
  `res/values/strings_archive.xml` (both `translatable="false"` until WS9,
  same convention as `strings_paywall.xml`).

## Integrator checklist (AnkyApp / AppContainer)

1. **Entitlement provider** — construct `RevealViewModel` with:
   ```kotlin
   entitledForGatingProvider = { entitlementStore.isEntitledForGating }
   ```
   The parameter defaults to `{ false }` (fail closed: unwired = veiled,
   never a free LLM call). Until wired, even subscribers see the veil.
2. **Paywall callback** — pass to `RevealScreen`:
   ```kotlin
   onOpenPaywall = { origin -> /* open PaywallSheet(origin) */ }
   ```
   The veil card and the "SEE WHAT ANKY SAW" CTA both call it with origin
   `"reflection_veil"`. Report the `veil_tapped {reflection}` funnel event
   at this call site (iOS does it inside the tap).
3. **In-app review** — pass `onRequestReview = { /* Play In-App Review */ }`
   (Play Core `ReviewManager`). The view model exposes
   `state.shouldRequestReviewAfterReadingFirstReflection` and
   `markFirstReflectionReviewRequested()`; persistence goes through the
   `didRequestFirstReflectionReviewProvider` /
   `persistFirstReflectionReviewRequested` constructor params — wire them
   to a prefs flag under key `anky.didRequestReviewAfterFirstReflection`
   (same key as iOS UserDefaults).
4. **Credits plumbing removal** — `RevealViewModel` keeps
   `creditsClient` / `reflectionCreditCache` / `hasClaimedFreeCreditsProvider`
   / `markFreeCreditsClaimed` as deprecated inert constructor params ONLY
   because AnkyApp.kt passes them by name. When AnkyApp drops them (credits
   deletion checklist in WIRING-subscription.md), delete the params.
   Likewise `RevealScreen(onOpenCredits = ...)` is accepted-and-ignored;
   drop it with the YouCredits route.
5. **Map tab** — no signature change: `MapScreen(viewModel, onOpenReveal,
   onOpenAllAnkys)` compiles as before; `onOpenAllAnkys` is now unused (the
   chamber has no stats-panel navigation). The `AnkyRoute.MapAllAnkys`
   route can be retired whenever AnkyApp is next touched.

## MirrorClient note (core/mirror — NOT edited by WS7)

The backend will refuse unentitled reflections with 402
`ENTITLEMENT_REQUIRED`; `MirrorClient.toMirrorErrorCode()` today only knows
`INSUFFICIENT_CREDITS`. WS7 maps BOTH to the veil in its own layer
(`isEntitlementDenied` in RevealViewModel.kt: `InsufficientCredits`,
`TrialAlreadyClaimed`, and any `Unknown`-code server error whose message
mentions ENTITLEMENT_REQUIRED / entitlement / subscription). When core/mirror
is next opened, add:

```kotlin
"ENTITLEMENT_REQUIRED" -> MirrorErrorCode.EntitlementRequired // new enum case
```

and extend `isEntitlementDenied` to match the new code — the message sniff
can then be removed.

## Known invariant fallout (not WS7's methods)

Deleting the credit UI makes these credits-era SourceInvariantTest methods
fail (they pin dead tokens like `showCreditPurchaseSheet`,
`state.needsCreditsToReflect`, `RevealCreditPurchaseSheet(`,
`R.string.get_more_credits`, credit-cache calls in RevealViewModel):

- `revealAutoStartReflectionIsOneShotLikeIos`
- `revealCompanionThinkingAndReflectionCopyMatchCurrentIos`
- `reflectionCreditBalanceCacheMirrorsIosPerAccountPersistence` (already
  failing against current iOS sources before WS7)

They belong to the credits-deletion cleanup (WIRING-subscription.md) and
need rewriting there. WS7's own six methods were rewritten:
`revealDeleteControlLabelAndDangerStyleMatchIos`,
`revealSubscriptionVeilReplacesCreditPurchaseSheet` (was
`revealCreditPurchaseSheetUsesCurrentIosCreditsSurface`),
`tagSessionsRefreshOnReturnLikeIosOnAppear`,
`archiveChamberIsTheLiveMapSurfaceOnLazureWall`,
`archiveChamberTitleAndDayHeadersUseIosSerifScale`,
`archiveChamberSearchCacheAndRowsMatchIosCanon` (the last three replace the
obsolete trail-map methods `mapDayDetailOwnsIosStyleTexturedBackground`,
`mapDayDetailTitleUsesIosInlineNavigationScale`,
`mapTrailNodeTextureUsesIosBlackFillAndColoredStroke`).

## Deferred / follow-ups

- Archive export (the sun button on iOS shares a .txt of all writings via
  the share sheet) — not ported yet; `core/storage/Exporter.kt` exists.
- Archive date-filter chip (iOS `selectedDate` deep link from the calendar)
  — the chamber takes no date argument yet; add when a calendar surface
  lands on Android.
- Localization for `strings_reveal.xml` / `strings_archive.xml` (WS9).
