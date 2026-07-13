# WIRING — WS6 onboarding (feature/onboarding)

The 13-screen onboarding is ported from
`ios/Anky/Features/Onboarding/OnboardingView.swift` (+ the screen-12/13
handling in `AppRoot.swift`). Everything lives in
`app/src/main/java/inc/anky/android/feature/onboarding/`:

| File | Contents |
| --- | --- |
| `OnboardingFlowState.kt` | Pure logic: screen ordering + paywall skip, swipe judgment, `wakingYears`, `OnboardingFlowProgress` (`anky.onboardingLastScreen`), `PhoneHoursBracket` (`anky.dailyPhoneHours`), `OnboardingJourneyStory` shape |
| `OnboardingScreen.kt` | `AnkyOnboardingFlow` (screens 1–12), `AnkyDayOneThresholdOverlay` (screen 13), sprite/dots/CTA pieces, deprecated `AnkyOnboardingScreen` wrapper |
| `res/values/strings_onboarding.xml` | All copy, keys `onboarding_*`, verbatim iOS English |

Tests: `app/src/test/java/inc/anky/android/onboarding/OnboardingFlowStateTest.kt`
plus the rewritten `firstLaunchOnboardingMatchesCurrentIosPages` in
`privacy/SourceInvariantTest.kt`.

## The composable contract

```kotlin
AnkyOnboardingFlow(
    dailyTargetStore = container.dailyTargetStore,           // core/gate
    writingAnchorStore = container.writingAnchorStore,       // core/gate
    eventLog = container.writeBeforeScrollEventLog,          // core/gate
    avatarStore = container.avatarStore,                     // core/storage
    flowPreferences = GateStorage.preferences(context),      // holds anky.onboardingLastScreen + anky.dailyPhoneHours
    isEntitledForGating = { container.entitlementStore.isEntitledForGating },
    onGateSetupRequested = { /* see below */ },
    onCompleted = { /* see below */ },
    onSyncTrialReminder = { /* entitlementStore.reconcileOnForeground() or TrialReminderSync hook */ },
    paywall = { onDone -> PaywallScreen(..., onDone = onDone) },        // WS-paywall
    gateSetup = { onDone -> GateSetupScreen(..., onDone = onDone) },    // WS-gate
)

AnkyDayOneThresholdOverlay(
    onStartWriting = { ... },
    progress = OnboardingFlowProgress(GateStorage.preferences(context)), // optional; marks 13 on appear
)
```

Exact signatures:

```kotlin
@Composable
fun AnkyOnboardingFlow(
    dailyTargetStore: DailyTargetStore,
    writingAnchorStore: WritingAnchorStore,
    eventLog: WriteBeforeScrollEventLogStore,
    avatarStore: AvatarStore,
    flowPreferences: SharedPreferences,
    isEntitledForGating: () -> Boolean,
    onGateSetupRequested: () -> Unit,
    onCompleted: () -> Unit,
    modifier: Modifier = Modifier,
    onSyncTrialReminder: () -> Unit = {},
    paywall: @Composable (onDone: () -> Unit) -> Unit,
    gateSetup: @Composable (onDone: () -> Unit) -> Unit,
)

@Composable
fun AnkyDayOneThresholdOverlay(
    onStartWriting: () -> Unit,
    modifier: Modifier = Modifier,
    progress: OnboardingFlowProgress? = null,
)
```

## Sequence (mirrors iOS AppRoot exactly)

1. Screens 1–11 run inside the flow's `HorizontalPager` (page = screen − 1,
   programmatic scrolling only; swipe gestures re-implement the iOS drag
   thresholds so the paywall can't be swiped past and the target slider owns
   its drag). `anky.onboardingLastScreen` is written on every move.
2. Screen 10 renders the `paywall` slot. While `isEntitledForGating()` is
   true the page is skipped in both directions and auto-advanced on landing
   (returning subscriber / restore / QA re-run — iOS `paywallScreen.onAppear`).
3. Screen 11 requests `POST_NOTIFICATIONS` (runtime ask on API 33+, treated
   as granted below), then calls `onSyncTrialReminder()` (iOS
   `entitlements.syncTrialReminder()` — the trial started one screen before
   the permission existed). Denied shows "You can turn this on later in
   Settings." for 1.4s, then continues anyway.
4. The flow marks screen 12, fires `onGateSetupRequested()` ONCE, and shows
   the `gateSetup` slot over a dawn wall. **The shell should use
   `onGateSetupRequested` to open the live writing surface underneath the
   flow** (iOS `presentDayOneThresholdIfNeeded`: blank session begun,
   writing portal opened) — the next stage is translucent over it.
5. When the `gateSetup` slot calls its `onDone` (Done *or* dismissal — iOS
   advances on either), the flow marks 13 and shows the Day 1 threshold
   overlay. The flow stage draws no wall of its own there, so whatever the
   shell placed beneath shows through the paper wash.
6. "Start writing" → the flow calls `OnboardingFlowProgress.markFinished()`
   (0) and then `onCompleted()`. **`onCompleted` is the ONLY place
   `anky.onboardingCompleted` may be set** — the shell must do
   `container.settingsStore.setOnboardingCompleted(true)`, hide the flow,
   and focus the writing keyboard (iOS `completeOnboarding()`).
   A relaunch mid-setup therefore restarts the flow, like iOS.

## Legacy wrapper (delete at integration)

`AnkyOnboardingScreen(startWriting, modifier)` is kept `@Deprecated` so
`AnkyApp.kt` compiles unchanged: it builds the stores from
`GateStorage.preferences(context)` / `AvatarStore(context)`, uses
`isEntitledForGating = { false }`, auto-advancing no-op paywall/gate-setup
slots, and maps `onCompleted → startWriting`. Integration should replace the
call with `AnkyOnboardingFlow` + real slots and then delete the wrapper (and
the legacy `onboarding_line_*` / `onboarding_cta_*` keys in `strings.xml`,
per PARITY WS6 "replace old 3-image onboarding entirely").

## Persisted keys (all iOS-identical)

| Key | Where | Meaning |
| --- | --- | --- |
| `anky.onboardingLastScreen` | `flowPreferences` | 1–11 in-view screens, 12 gate setup, 13 Day 1 threshold, 0 finished |
| `anky.dailyPhoneHours` | `flowPreferences` | chosen bracket raw value: `1-2` / `3-4` / `5-6` / `7+` |
| `anky.writerName` | via `WritingAnchorStore.save` | optional name (screen 7) |
| `writeBeforeScroll.dailyTarget.v1` | via `DailyTargetStore.setInitialTarget` | screen 8 choice, applies immediately |
| event `onboarding_target_set` | via event log | metadata `targetMinutes`, `changedFromDefault` |
| `filesDir/avatar.jpg` | via `AvatarStore` | selfie, JPEG quality 85, never leaves the device |

## Slot expectations

- **Paywall slot (screen 10):** full-bleed inside the pager page, dawn
  LazureWall behind it (the flow paints it). Call `onDone()` after purchase
  OR when its own skip affordance is used (`paywallIsSkippable` lives inside
  the paywall, like iOS). Note the page composes only when visible/adjacent;
  record `paywall_shown` on first composition, it will not re-fire on
  re-entry from the same settle.
- **Gate setup slot (screen 12):** rendered full-screen above a dawn wall.
  MUST call `onDone()` on every exit path (Done, back, dismiss) — iOS
  crosses into Day 1 `onDismiss` however the sheet closes.

## Fidelity deviations (documented, deliberate)

- iOS crossfades screens in place; Android uses `HorizontalPager` with
  gesture rules preserved (spec decision). Timing beats, copy, palette,
  screen order, and skip logic are 1:1.
- The Day 1 overlay's `.ultraThinMaterial` blur is approximated with two
  paper washes (0.35 deep + 0.55 paper), same as VeilCard's stand-in.
- Sprites reuse the shared `anky###` frames at the `AnkyPresenceOverlay`
  windows (wave 23–26, shy 52–57, seated 46–51, idle 1–6) at 6fps.
- Selfie capture uses `TakePicturePreview` + front-camera intent hints
  (CameraX is not a dependency); iOS embeds a camera picker.
- `WritingAnchorStore.writerName` substitutes "You" when unset on Android;
  the journey story filters that placeholder so the third-person variant
  only appears for a real name.
- All `onboarding_*` strings are `translatable="false"`: iOS
  `AnkyLocalization.ui` falls back to the English key for this copy (none of
  it is in any `Localizable.strings` table), so every iOS locale sees
  English here too. Flip to translatable when iOS grows the translations.
