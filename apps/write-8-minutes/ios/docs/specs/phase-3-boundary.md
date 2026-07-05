# Phase 3 — The Boundary (implemented July 2026)

Entitlements, veils, and the paywall that respects people. This document
records what was built and the decisions that shaped it, for the next session
that has to touch any of it.

## The philosophy, enforced in code

1. **Protection is never revoked for non-payment.** The gate, shield, Quick
   Passes (3/day), and the emergency breath work forever, for everyone. No
   code path drops them on lapse. The `LapsedPaywallScreen` hard overlay was
   **removed** — a lapse is a narrowing, not a death.
2. **Nothing is ever lost.** Seconds always count. `LevelProgressStore`'s
   counter and the server's `session_ledger` are never touched by
   entitlement; only *presentation* holds at the boundary.

## The entitlement matrix (enforced server-side)

| Capability | Free | Trial/Paid |
|---|---|---|
| Gate / shield / Quick Pass / emergency breath | ✓ always | ✓ |
| Writing, keystroke capture, seconds counted, strokes landing | ✓ always | ✓ |
| Daily Unlock (target → day open) | ✗ | ✓ |
| Reflections (any session length) + server nudges | ✗ veiled | ✓ |
| Level-up ceremonies | first only (1→2) | ✓ |
| Painting generation | level-2 package only | ✓ |
| Journey map (pager page 2) | ✗ veiled | ✓ |

Free-tier sessions make **zero LLM calls**: clients never ask, and the server
answers `402 ENTITLEMENT_REQUIRED` if they do. The DeviceCheck "2 free device
reflections" gift is off (`anky.automaticTrials` = false); the 3-day
subscription trial is the only trial. Previously **purchased** credits and
the x402 crypto path are still honored — paid value is never clawed back.

## Server truth: how the backend learns subscription state

**Choice: client-pushed StoreKit 2 transaction JWS + App Store Server
Notifications V2. Not a RevenueCat webhook** — purchases are pure StoreKit 2
(no RC SDK in the app; RevenueCat is only the legacy virtual-currency credit
ledger), so RC never sees subscription events.

- `POST /subscription/sync` `{signedTransaction}` — EIP-712 signed like every
  Anky request. The app pushes its current entitlement JWS after purchase,
  restore, renewal, and (deduped, `subscription/store.ts` guard by Apple's
  `signedDate`) on foreground. This binds **wallet ↔ originalTransactionId**.
- `POST /appstore/notifications` — ASN V2. Apple's certificate chain IS the
  authentication; notifications are joined to accounts via
  `original_transaction_id` from prior syncs (unmapped ones are acked and
  dropped). Handles refunds (`revocationDate` → entitlement off; delivered
  assets stay), renewals, and billing grace (`gracePeriodExpiresDate`).
  **Operator TODO: set the webhook URL in App Store Connect →
  App Information → App Store Server Notifications (V2), production:
  `https://mirror-production-a23c.up.railway.app/appstore/notifications`.**
- JWS verification: `backend/subscription/applejws.ts` — x5c chain verified
  down to the **pinned Apple Root CA-G3** (base64-embedded in source so no
  deploy step can drop it), Apple marker OIDs checked, ES256 via WebCrypto,
  validity at Apple's `signedDate`. Test chain fixture at
  `backend/test/fixtures/apple-jws-fixture.json` (test-only key, not a secret).
- State: `subscription_state` table (level/db.ts), one row per account.
  Entitled = unrevoked ∧ (unexpired ∨ in grace). `accountEntitlement()` in
  `subscription/store.ts` is the one question every gate asks.
- The app sets `appAccountToken` (UUID derived from the wallet address,
  `EntitlementStore.walletAppAccountToken`) on every purchase going forward.

**Race-safe pay → generate → ceremony:** `EntitlementStore.purchase()` awaits
`syncEntitlementToBackend()` before returning; AppRoot's
`onChange(isEntitled)` re-syncs then calls
`LevelPaintingCoordinator.handleEntitlementConfirmed()`. If the sync races or
fails, `/level/prepare` 402s, the phase reverts to `accumulating`, and the
next foreground heals it — the server gate is the invariant, the client
ordering the fast path.

## Server gates

- `/anky` (reflection + nudge intents): entitled → reflect with **no credit
  spend** (`source: "subscription"`); free → purchased-credit balance or
  x402, else `ENTITLEMENT_REQUIRED`.
- `/level/prepare`: `level > 2` requires entitlement, checked **before** any
  pipeline state so pre-generation never spends for free accounts.
  `FREE_GENERATION_MAX_LEVEL = 2` (painting/routes.ts).
- `/level/assets/*`: ungated — generated packages stay downloadable forever.

## Client: the boundary and the veils

- `LevelProgressStore.freeBoundaryLevel = 2`; `presentedProgress(entitled:)`
  clamps presentation to level 2 at a serene 100% (true totalSeconds carried
  through); `isAtBoundary(entitled:)`; `claimBoundaryReport` fires
  `boundary_reached` once per life.
- `LevelPaintingCoordinator.entitledForGating` (kept fresh by AppRoot) gates
  the p95 pre-generation trigger past level 2 and holds the owed ceremony —
  **unless its package is already installed** (lapse grace: a generated
  painting always gets its ceremony).
- `VeiledFeature` (Support/AnkyLazure.swift): the feature's real UI under a
  parchment mist + breathing watercolor, the spiral sun glyph (no padlocks,
  no red, never pure black), one quiet registry line, whole surface → paywall
  sheet; fires `veil_tapped {surface}`. Applied to exactly three surfaces:
  1. **Reflection** — sealing flow (`MirrorAndGateBeatView`) and archive
     (`RevealView`), copy `veilReflection`.
  2. **Ceremony at the boundary** — tapping the held painting opens
     `BoundaryCeremonyVeilView` (PaintingHomeView.swift), copy `veilCeremony`.
  3. **Journey map** — pager page 2 misted, sprite waiting at tile 1
     (`JourneyMapView(heldAtFirstTile:)`), copy `veilJourney`.
- `PaywallSheet` (PaywallView.swift): the existing paywall as a sheet,
  `Context.veil(origin:)` (copy only), Restore Purchases present, dawn
  register, no countdowns/scarcity ever.
- Daily Unlock: `UnlockPolicy.grant(dailyUnlockEntitled:)` +
  `WriteBeforeScrollSessionMetricTracker` — free writers at target earn a
  Quick Pass, never the day. Adaptive-target offers are entitled-only
  (AppRoot). Emergency breath untouched.
- Ambient truth: widget shows the earned painting + spiral + "a new painting
  waits" at the boundary (`GlanceSnapshot.isAtBoundary`), quick action says
  `boundaryQuickAction`, both deep-link `anky://painting`. The trial Live
  Activity respects `PaywallPressureLedger` — one rolling week of quiet after
  *any* paywall was shown, across all surfaces.

## Funnel (§6)

Signed events, hashed accounts, nothing about writing:
`ceremony_1_shown → boundary_reached → veil_tapped {surface} →
paywall_shown {origin} → trial_started / subscribed / restored → lapsed`.
Client: `AnkyFunnel` (LevelSyncClient.swift). Server: `POST /events/funnel`
(whitelist) → `funnel_events` table → `GET /debug/funnel` (admin key, 30-day
counts by event and origin).

## Canon note

DESIGN.md §6 ("the two tiers stay two", Daily Unlock for everyone) was
amended July 2026: the Daily Unlock is part of the subscription; Quick Passes
and the emergency breath remain everyone's forever. See the dated amendment
in DESIGN.md §8.

## QA

`EntitlementStore.ignoresEntitlementForQA = true` forces the free tier
everywhere (veils, boundary, no LLM calls) even after a test purchase.
`AppRoot.alwaysShowsOnboardingForQA` — both MUST be false before shipping.
