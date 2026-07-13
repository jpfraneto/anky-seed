# WIRING — WS2 gate runtime + gate UI (Android blocking runtime)

The platform half of Write Before You Scroll: where iOS hands
FamilyControls/ManagedSettings/DeviceActivity a shield to enforce, Android
enforces it itself. Builds strictly ON Phase A (`core/gate/**`,
`core/copy/AnkyCopyRegistry`, `ui/lazure/**`) — nothing in those packages was
touched. This doc is the integration contract for the AppContainer /
navigation / writing-surface workstreams.

## What exists now

Package `inc.anky.android.core.gate.runtime` (service / alarms / watcher):

| File | iOS counterpart | Contents |
| --- | --- | --- |
| `BlockedAppSelectionStore.kt` | `BlockedAppSelectionStore.swift` | `BlockedApp(packageName, label)` list, JSON at the iOS key `writeBeforeScroll.blockedAppSelection.v1` (payload diverges by design: Android knows its apps; iOS only stores opaque tokens). Pure `encode`/`decode` for tests. |
| `GateWatcherPolicy.kt` | (new; the pure heart of the watcher) | `verdict(foregroundPackage, blocked, own, gateOff, state, now)` → `LaunchShield/None`; `needsStateReconcile` (tick belt-and-braces, writes only on disagreement); `shouldLaunchAgain` (2s launch debounce). All routed through `WriteBeforeScrollShieldReconciler`. |
| `AndroidShieldPort.kt` | `ScreenTimeShieldController.swift` | Implements Phase A's `ShieldPort`. `applyShield` **marks** state (`shieldActive`, counts, clears unlock fields, `lastRelockedAt`) — the watcher enforces. Same guards as iOS: off-switch → clear + false; no usage access (≙ ScreenTime authorization) → clear + error + `relock_failed`; empty selection → clear + error + `relock_failed`. Transition-only `shield_applied`/`shield_cleared` via `appendShieldTransition`. Also ports `reconcileShield` (logs `relock_applied` when an expired unlock re-armed). |
| `AlarmRelockScheduler.kt` | `ScreenTimeUnlockScheduler.swift` | Implements `RelockSchedulerPort`: `setExactAndAllowWhileIdle(RTC_WAKEUP)` → `RelockReceiver`; `RelockPlanner` (pure) refuses windows ≤ 5s like iOS; `relock_scheduled`/`relock_failed` events. Android-14 exact-alarm denial falls back to `setWindow(…, 60s)` — the watcher tick is the true backstop. |
| `RelockReceiver.kt` | `DeviceActivityMonitorExtension.swift` | Alarm fired → reconciler decision (off-switch outranks the alarm) → `reconcileShield` + `applyingRelock` state machine on success → `ensureRunning`. |
| `BootReceiver.kt` | (iOS shield survives reboot; Android must re-arm) | BOOT_COMPLETED → re-schedule the relock alarm if an unlock window is still open (alarms die at reboot) → reconcile → restart watcher. |
| `GateWatcherService.kt` | ManagedSettings enforcement + monitor extension | `specialUse` FGS. Coroutine loop: `UsageStatsManager.queryEvents` since last tick, ~800ms while screen on, 15s reconcile-only beat while off (SCREEN_ON/OFF receiver). Foreground package kept **sticky** across ticks so an unlock expiring mid-scroll shields immediately. Verdict → `ShieldActivity` (`FLAG_ACTIVITY_NEW_TASK`). Quiet notification: channel `anky_gate`, IMPORTANCE_LOW, silent, registry-toned copy. `START_STICKY`; stops itself when `shouldRun` turns false. |
| `GateRuntimeController.kt` | spike VM's forceLock/turnGateOff/saveSelection | `ensureRunning`/`stop` (service runs iff `!gateOff && selection.isNotEmpty()` — including through unlock windows), `turnGateOn` (= iOS `forceLock`: off-switch back on, clearUnlock, cancel alarm, `forcingLock`, apply), `turnGateOff` (honest exit: flag, cancel alarm, clear, `shield_cleared {reason: gateSwitchOff}`, stop service), `saveSelection` (persist + `app_selection_saved` + reconcile — the reconciler keeps the off-switch outranking the save), `reconcileOnAppActive`. |
| `GateUnlockApplier.kt` | spike VM `applyUnlock` + `completeEmergencyBreath` | The one unlock sequence: optional quick-pass consumption (`quick_pass_used`, gate-originated writing only) → `UnlockStateStore.apply` → shield down → `applyingUnlock` → `unlock_granted {source, unlockedUntil}` → relock scheduled. `applyEmergencyUnlock()` = daily-until-local-midnight, source `emergency`, **no pass consumed**. |
| `UsageAccess.kt` | `AuthorizationCenter` status | Live AppOps check (never persisted, per WIRING-gate.md). |
| `GateDeepLinks.kt` | shield → app launch bridge | `anky://write`, `anky://emergency` as **explicit** VIEW intents to MainActivity. |

Package `inc.anky.android.feature.gate` (UI):

| File | iOS counterpart |
| --- | --- |
| `ShieldActivity.kt` + `ShieldScreen.kt` | `ShieldConfigurationExtension` + `ShieldActionExtension` in one full-screen activity. Exact iOS palette (bg 0.08/0.055/0.045, gold title 0.96/0.86/0.68, warm subtitle 0.78/0.67/0.58), `anky_shield_door_icon`, registry headline (3 lines rotating by day-of-year, exhausted variant at 0 passes), `gateFooter("{App} is waiting behind the door.")`, `gatePassLine`, primary `ThreadButton` "Write ⊙", quiet `emergencyLink`. Back → `moveTaskToBack` (home, never the blocked app). `onResume` obeys the reconciler and steps aside once unlocked. |
| `EmergencyBreathScreen.kt` (+ `EmergencyBreathRoute`) | `EmergencyBreathView.swift`: 30s date-anchored breath, pale veil swelling on the 8s clock, 236dp gold hairline ring (0.16 track / 0.42 fill, 1.5dp round cap, −90° start), chevron cancel. Backgrounding (ON_STOP) cancels — no partial credit. Route wrapper applies the emergency grant and takes `onReportEmergencyUnlock` as a callback. |
| `AdaptiveTargetOfferCard.kt` | `AdaptiveTargetOfferView.swift`: registry copy, gold-light filled "walk with N" + outlined "keep N". |
| `GateSetupScreen.kt` | `GateSetupView.swift`: authorize → chooseApps → turnOn → done, one caption + one ThreadButton per step, "later" skip, done-step "turn the gate off" link with the registry confirmation. Authorize = Android permission funnel (below). ChooseApps = launcher-app picker (search, checkboxes, curated icons, social preselect). |
| `BlockedAppIconCatalog.kt` | `GateSetupView.iconNameByIdentifier`: package → `blocked_*` drawable (16 icons), exact-then-fuzzy like iOS ("x" exact-only), fallback = real app icon. Preselect = social subset only (never Chrome/WhatsApp — a preselected browser is a trap, not a kindness). |

Resources: `res/values/strings_gate.xml` (notification, FGS explanation,
setup/picker chrome). Registry lines are used verbatim from
`AnkyCopyRegistry.kt` — they are deliberately NOT duplicated into resources
(localization workstream decision pending, matching WIRING-gate.md).

Tests (`app/src/test/java/inc/anky/android/gate/runtime/`):
`GateWatcherPolicyTest` (shield decisions, off-switch, relock reconcile,
debounce), `BlockedAppSelectionStoreTest`, `RelockPlannerTest`,
`BlockedAppIconCatalogTest`. Pure JVM, no Robolectric.

## How the runtime maps each iOS behavior

| iOS | Android |
| --- | --- |
| ManagedSettings applies a shield the OS renders | `GateStateStore.shieldActive` is the mark; `GateWatcherService` polls UsageStats and launches `ShieldActivity` over blocked apps while the reconciler says locked |
| ShieldConfiguration extension renders per-app | `ShieldScreen` reads the intercepted package/label from the launch intent |
| ShieldAction primary → notification/direct-open bridge to the app | Same process: explicit `anky://write` intent + `pendingInterventionRequestedAt` marker (survives a lost intent; MainActivity routing can consume it like iOS `handlePendingInterventionIfNeeded`) |
| ShieldAction secondary → emergency intent | Explicit `anky://emergency` intent; `shield_action_tapped {action}` + `emergency_unlock_tapped` logged at the tap, like the iOS action extension |
| DeviceActivity `intervalDidEnd` relock | `AlarmRelockScheduler` → `RelockReceiver`; belt-and-braces = every service tick reconciles (and the app-foreground hook below) |
| Screen Time authorization | Usage access (live AppOps check) |
| Shield survives reboot (OS-owned) | `BootReceiver` re-arms alarm + state + service |

## Integration needs (for AppContainer / nav / MainActivity owners)

1. **Service start hooks.** Call `GateRuntimeController.reconcileOnAppActive(context)`
   on app foreground (e.g. AnkyApp's ON_RESUME observer). That is the
   reconcile point WIRING-gate.md rule 2 asks for AND the guaranteed-legal
   place to (re)start the FGS after force-stops. Everything else
   (setup screen, boot, relock alarm, selection save) already calls
   `ensureRunning` itself.
2. **Deep-link routing.** No `anky://` intent-filter was added (this phase
   sends *explicit* intents). MainActivity must route `intent.data`:
   `anky://write` → writing surface with `isGateOriginatedSession = true`;
   `anky://emergency` → `EmergencyBreathRoute(onFinished, onReportEmergencyUnlock = { LevelSyncClient.reportEmergencyUnlock(identity) })`.
   Handle both `onCreate` and `onNewIntent` (launchMode `singleTop`), and
   consume `pendingInterventionRequestedAt` (clear it + log
   `anky_opened_from_shield_pending_state`) as the fallback route, mirroring
   iOS.
3. **Unlock ladder.** The writing surface should apply ladder grants through
   `GateRuntime(context).unlockApplier.applyUnlock(grant, source)` — it does
   passes/state/log/relock in the iOS order.
4. **Gate setup entry.** `GateSetupScreen(onDone)` is self-contained
   (constructs `GateRuntime` itself); onboarding/You can present it directly.
5. **Adaptive offer.** `AdaptiveTargetOfferCard(offer, onLower, onKeep)` is
   presentation-only; the caller evaluates `AdaptiveTargetPolicy` and marks
   `AdaptiveTargetOfferStore`.

## Platform decisions & caveats

- **FGS type**: `specialUse` + `PROPERTY_SPECIAL_USE_FGS_SUBTYPE`
  explanation (Play Console declaration required at submission). Fallback
  reasoning: no other Android 14 type fits (`dataSync` is for transfers,
  `health` is sensor-bound, `mediaPlayback` is dishonest); digital-wellbeing
  blockers are the canonical specialUse example. Pre-34 devices ignore the
  type; `startForeground` passes the typed overload only on 34+.
- **Shield-over-app launch**: activity starts from the background are
  restricted on Android 10+; holding `SYSTEM_ALERT_WINDOW` is the documented
  exemption, so the setup funnel requests "display over other apps" as a
  *required* permission on API 29+ (PARITY platform-decisions table:
  `canDrawOverlays` fallback). On 26–28 it is optional.
- **Permission funnel UX** (authorize step): usage access (required; opens
  `ACTION_USAGE_ACCESS_SETTINGS` — a Settings *list*, the writer must find
  Anky in it; caption says why), display-over-apps (required on 29+),
  notifications (optional; runtime prompt on 33+), battery-optimization
  exemption (optional, with the "OEM reality" caption; needs
  `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, Play-sensitive but accepted for
  user-facing wellbeing blockers). The step auto-advances once the required
  pair is granted; optional rows stay tappable while on the step.
- **Exact alarms**: `SCHEDULE_EXACT_ALARM` can be user-revoked (and is
  default-denied on 14 for new installs); `canScheduleExactAlarms()` guards
  the call with a 60s `setWindow` fallback. The 800ms watcher tick makes a
  late alarm cosmetic.
- **`<queries>` over `QUERY_ALL_PACKAGES`**: the picker only needs
  MAIN/LAUNCHER-resolvable apps — intent-scoped visibility, no Play
  declaration needed.
- **Boot receiver** is `exported="false"`: protected system broadcasts are
  delivered regardless.
- **Event fidelity**: `shield_shown` once per interception (activity create /
  package change; iOS's `shield_rendered` fires per OS render and is not
  reproduced), `shield_action_tapped {action: write|emergency}` per tap,
  `quick_pass_exhausted_shown` at 0 passes, everything else via Phase-A
  stores.
- **Sprites**: iOS centers the emergency breath / adaptive offer on Anky
  sprites; the sprite sheets aren't ported yet, so `AnkySunGlyph` holds those
  centers. Swap when a sprites workstream lands.
- **strings_gate.xml is values/ only** — localized variants (values-es etc.)
  belong to the localization workstream, same as the registry.
- **OEM reality**: on aggressive OEMs (Xiaomi/Oppo/vivo) the FGS can still be
  killed despite the exemption; every entry point re-arms (boot, alarm, app
  foreground, START_STICKY restart), which is the honest best available.
