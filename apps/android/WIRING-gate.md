# WIRING — WS2 gate engine (core/gate + core/copy)

Pure-logic port of the iOS Write Before You Scroll engine
(`ios/Anky/Core/WriteBeforeScroll/`). No existing file was touched; this doc
is the integration contract for the workstreams that wire it up
(AppContainer, blocking runtime, writing surface, onboarding, You/settings).

## What exists now

Package `inc.anky.android.core.gate`:

| Kotlin file | iOS source | Contents |
| --- | --- | --- |
| `UnlockPolicy.kt` | `UnlockPolicy.swift` | `UnlockTier` (`quick_pass`/`daily_unlock`), `UnlockGrant`, `GateWritingSnapshot`, `UnlockPolicy` (grant ladder, sentence/word rules, constants 900s / 3/day / 8min / 6 words), `WriteBeforeScrollUnlockLadderAction` + `WriteBeforeScrollUnlockLadder`, `FreeTargetMomentLedger` (`anky.freeTargetMoment.lastShownDay`) |
| `UnlockStateStore.kt` | `UnlockStateStore.swift` | `UnlockState`, `WriteBeforeScrollUnlockOfferPolicy`, `UnlockStateStore` (`writeBeforeScroll.unlockState.v1`) |
| `QuickPassStore.kt` | `QuickPassStore.swift` | 3/day, local-midnight reset (`writeBeforeScroll.quickPasses.v1`) |
| `DailyTargetStore.kt` | `DailyTargetStore.swift` | 1–8 min, default 8, onboarding-immediate vs next-day edits (`writeBeforeScroll.dailyTarget.v1`) |
| `GateStateStore.kt` | `WriteBeforeScrollScreenTimeStateStore.swift` + `WriteBeforeScrollUnlockStateMachine.swift` | `GateState` + `GateStateStore` (`writeBeforeScroll.screenTimeState.v1`), `WriteBeforeScrollGateSwitchStore` (`writeBeforeScroll.gateOff.v1`), `WriteBeforeScrollShieldReconciler`, `WriteBeforeScrollUnlockSource`, `WriteBeforeScrollUnlockStateMachine` |
| `GatePorts.kt` | ManagedSettings / DeviceActivity seams | `ShieldPort`, `RelockSchedulerPort` — implemented later by the Android blocking runtime |
| `AdaptiveTargetPolicy.kt` | `AdaptiveTargetPolicy.swift` | 2 consecutive missed days → halve offer; `AdaptiveTargetOfferStore` (`writeBeforeScroll.adaptiveOffer.v1`) |
| `SignalState.kt` | `SignalState.swift` | `SignalSnapshot`, `SignalCalculator` (11×streak + 12, cap 100), `EightDayGate` day titles |
| `EightDayGateStore.kt` | `EightDayGateStore.swift` | `anky.wbs.eightDayGateProgress.v1` |
| `FirstGateStore.kt` | `FirstGateStore.swift` | `anky.wbs.hasCompletedFirstGate`, `anky.wbs.postFirstGatePaywallSeen` |
| `WritingAnchorStore.kt` | `WritingAnchorStore.swift` | `anky.writerName`, `anky.wbs.anchorSentence`, composed shield arrival message |
| `WriteBeforeScrollEventLogStore.kt` | `WriteBeforeScrollEventLogStore.swift` | 39 event names (exact iOS raw strings), max 300, `appendShieldTransition` |
| `WriteBeforeScrollSessionMetrics.kt` | `WriteBeforeScrollSessionMetrics.swift` | golden-metric tracker, availableTiers mirror of the ladder |
| `GateStorage.kt` | `AppGroupStorage.swift` (collapsed) | one prefs file `anky-write-before-scroll` for all gate keys |

Package `inc.anky.android.core.copy`: `AnkyCopyRegistry.kt` — every string
verbatim from `AnkyCopyRegistry.swift` (gate headlines/exhausted/footer/pass
line, quick-pass unlock, top bar, ceremony, journey, adaptive, emergency,
gate off-switch, free-target moment, veils, boundary, quick action, trial,
paywall sheet, painting disclosure).

## Construction / DI (for AppContainer, later)

Every store takes a constructor-injected `android.content.SharedPreferences`
(JVM-testable, matches `SharedPreferencesReflectionCreditCache` style). Use
one instance for all of them:

```kotlin
val gatePrefs = GateStorage.preferences(context)   // "anky-write-before-scroll"
val quickPassStore = QuickPassStore(gatePrefs)
val dailyTargetStore = DailyTargetStore(gatePrefs)
val unlockStateStore = UnlockStateStore(gatePrefs)
val gateStateStore = GateStateStore(gatePrefs)
val gateSwitchStore = WriteBeforeScrollGateSwitchStore(gatePrefs)
val eventLog = WriteBeforeScrollEventLogStore(gatePrefs)
// … FirstGateStore, WritingAnchorStore, EightDayGateStore,
//   AdaptiveTargetOfferStore, FreeTargetMomentLedger likewise
```

Time is injectable everywhere (`now: Instant`, `zoneId: ZoneId`,
`GateStateStore(now = ...)`) — production code can use the defaults.

## Runtime contract (blocking-runtime workstream)

1. Implement `ShieldPort` (apply = start blocking selected packages,
   clear = stop) and `RelockSchedulerPort` (AlarmManager at
   `grant.unlockedUntil`).
2. On every reconcile point (app foreground, watcher tick, alarm fire),
   call `WriteBeforeScrollShieldReconciler.decision(gateSwitchStore.isGateOff,
   gateStateStore.load(), now)` and obey it. **The off-switch outranks every
   re-arm path** — while `isGateOff` the only legal move is clearing; do not
   re-arm on selection save either (iOS decision 2026-07-06).
3. Use `WriteBeforeScrollUnlockStateMachine.applyingUnlock/forcingLock/
   applyingRelock` to mutate `GateState` — never hand-roll transitions.
4. Log `shield_applied`/`shield_cleared` only on transitions via
   `WriteBeforeScrollEventLogStore.appendShieldTransition(wasActive, isActive)`
   (iOS `ScreenTimeShieldController` behavior).
5. `GateState` keeps the iOS field shape. Map: `selectedApplicationCount` =
   blocked-package count; `selectedCategoryCount`/`selectedWebDomainCount`
   stay 0 until Android grows equivalents.

## Writing-surface contract

- Map the session engine state into `GateWritingSnapshot(reconstructedText,
  elapsedMs)` on each accepted batch.
- Drive `WriteBeforeScrollSessionMetricTracker.recordAcceptedCharacters(...)`
  per accepted batch; append the returned `events` to the event log; feed
  `update.availableGrant` plus `UnlockState` into
  `WriteBeforeScrollUnlockLadder.action(...)`.
- Ladder actions: `ApplyQuickPassively` → consume a pass
  (`QuickPassStore.consumePass`), apply grant (`UnlockStateStore.apply` +
  state machine + `ShieldPort.clearShield` + `RelockSchedulerPort.scheduleRelock`),
  log `quick_pass_used`; `UpgradeToDaily` → replace window in place;
  `Offer` → hold for the sealing screen's gate button;
  `OfferFreeTargetMoment` → show moment screen once/day
  (`FreeTargetMomentLedger`); `Withdraw` → clear any held grant.
- Quick grants are gate-exclusive: pass `isGateOriginatedSession` only when
  the session was launched from the shield.

## Deviations from iOS (and why)

- **Storage**: iOS App Group `UserDefaults` + Codable/ISO-8601 JSON →
  single-process `SharedPreferences` + org.json/ISO-8601 strings. Keys are
  byte-identical to iOS; only the container differs (no extensions on
  Android — the watcher runs in-process).
- **`WritingSessionSnapshot` → `GateWritingSnapshot`**: only the two fields
  the gate judges (`reconstructedText`, `elapsedMs`); the protocol-level
  fields stay with the writing engine workstream.
- **`GateWritingSnapshot.hasCompletedSentence`** mirrors iOS
  `WritingSessionSnapshot.hasCompletedSentence`, which is the *quick*
  variant (`hasCompletedQuickSentence`: terminal punctuation OR ≥6 words).
- **`WriteBeforeScrollScreenTimeState` → `GateState`**, same fields/keys;
  ScreenTime authorization state has no Android analogue — usage-access is a
  runtime permission checked live, not persisted here.
- **Tier/date typing**: Swift `Date` → `java.time.Instant`; `Calendar` →
  injectable `ZoneId`. `FreeTargetMomentLedger` stores epoch millis (iOS
  stored a `Date` object in defaults).
- **Copy registry**: `ceremonyLine` formats seconds with `Locale.US`
  grouping (iOS used locale-aware `.formatted()`); verbatim English pending
  the localization workstream.
- **Not ported here (runtime workstream)**: `ScreenTimeShieldController`,
  `ScreenTimeUnlockScheduler`, `ScreenTimeSelectionStore`,
  `BlockedAppSelectionStore`, launch-bridge stores/resolvers,
  `WritingSessionEngine` glue.
- **Tests**: all of `UnlockLadderTests`, `GateSwitchTests`,
  `SignalStateTests` (minus the two `WritingSessionEngine` draft/seal cases,
  which belong to the protocol workstream), `AdaptiveTargetPolicyTests`, and
  the policy/metric-tracker/store cases of `WriteBeforeScrollTests` were
  ported 1:1; engine-driven cases feed equivalent snapshots directly.
