# WIRING — WS7 writing surface + sealing flow (`feature/write`)

Everything below is built and unit-tested inside `feature/write/**`; nothing
outside it was touched. This file is the integration contract for whoever
owns AnkyApp/AppContainer.

## New public surface (all additive, all defaulted — current call sites compile unchanged)

`WriteViewModel` gained defaulted constructor params:

```kotlin
WriteViewModel(
    ...existing...,
    writingPreferencesStore = container.writingPreferencesStore,   // WritingPreferencesStore(context)
    gateSession = GateSession(GateStorage.preferences(context)),   // facade in feature/write
    entitledForGating = { entitlementStore.state.value.isEntitledForGating },
    onSealedComplete = { hash, durationMs, replacedDurationMs, sealedAtMs ->
        levelProgressStore.creditSealedSession(hash, durationMs, replacedDurationMs, sealedAtMs)
        appScope.launch { LevelSyncClient.flushUnreported(...) }   // + glance sync
    },
    onUnlockAvailable = { grant -> /* optional: surface availability */ },
    onApplyUnlock = { grant ->
        // Blocking runtime: state machine + ShieldPort.clearShield +
        // RelockSchedulerPort.scheduleRelock(grant.unlockedUntil).
        // QuickPassStore/UnlockStateStore are ALREADY updated and
        // quick_pass_used already logged by the VM/GateSession.
    },
)
```

`WriteScreen` gained defaulted params: `freeTargetMoment: (@Composable () -> Unit)?`
(paywall agent's FreeTargetMomentCard slot), `onSealingDone` (defaults to
`onCloseToMap`; iOS lands on the painting home — repoint when the shell has
one), `onSealingUnlock: (UnlockGrant) -> Unit` (gate-originated return-to-app
loop), `onOpenPaywall: (String) -> Unit` (origins `"reflection"` /
`"free_target_moment"`), `onEmergency: () -> Unit` (emergency breath).

`WriteViewModel` new API: `markGateOriginatedSession(appDisplayName)` (call
when routing from the shield), `sealIfLeftInMotion()` (WriteScreen already
calls it on ON_STOP), `consumeAvailableUnlockGrant()`, `applySealingUnlock()`,
`finishSealing()`, `stayAfterSealing()`, `beginSealedSessionReflection()`,
`markFreeTargetMomentPresented()`, `requestBackspace()`,
`nudgeInvalidInput(RejectedWritingInput)`.

## Behavior changes the shell should adopt (not source-breaking)

1. **Sealing no longer emits `completedHash`.** `WriteState.completedHash`
   stays (always null after a seal) so AnkyApp's collectors compile; the
   post-seal surface is `PostSessionSealingScreen`, hosted inside
   WriteScreen. AnkyApp's `openPostWriteReveal` now fires only for imports
   (`onImported`). When the shell is reworked (WS8), delete the
   `completedHash` collectors and `consumeCompletedHash` plumbing.
2. **Rejected input speaks through `WriteState.rejectedInputMessage`**
   (registry lines, rendered in-surface). `errorMessage` no longer carries
   the old onboarding line — AnkyApp's `localizedWriteErrorMessage` mapping
   for it is dead and its overlay no longer fires on rejected keys.
3. **Nudges**: `entitledForGating` defaults to `{ true }` (iOS default), so
   today's behavior (mirror nudge, mirror sealing reflection) is unchanged
   until the entitlement provider is wired. Wire it to make free sessions
   local-nudge + veiled-reflection (zero LLM calls).
4. **`onSealedComplete` signature** is `(hash, durationMs, replacedDurationMs,
   sealedAtMs)` — durationMs not seconds, because
   `LevelProgressStore.creditSealedSession` takes durationMs and needs
   `replacedDurationMs` for continued sessions (delta-crediting).
5. **`gateGoBackTo(appName)`** is not in `AnkyCopyRegistry` yet; the sealing
   screen uses `R.string.write_sealing_go_back_to` ("go back to %1$s" /
   "the app"), matching iOS `WriteBeforeScrollReturnTarget.gateLabel()`.
   WS9 should move it into the registry + locales.
6. **Return-to-app loop**: iOS opens the attempted app's URL after a
   gate-originated unlock. Android equivalent (launch intent for the blocked
   package) belongs to the blocking runtime via `onSealingUnlock`.
7. **Strings**: `res/values/strings_write.xml` is new, all
   `translatable="false"` until WS9 localizes (keeps
   `LocalizationResourceTest` green).

## GateSession (feature/write facade over core/gate)

`GateSession(SharedPreferences)` wraps UnlockStateStore, QuickPassStore,
DailyTargetStore, WriteBeforeScrollEventLogStore, FreeTargetMomentLedger,
FirstGateStore + UnlockPolicy/UnlockLadder/OfferPolicy. The VM logs
`writing_started`, `sentence_unlock_available`, `daily_target_reached`,
`quick_pass_used`, `unlock_tapped`, `session_overshoot`,
`wbs_session_sealed` and drives the ladder per accepted glyph. Passive quick
apply consumes the pass and opens the unlock window itself; `onApplyUnlock`
only needs to clear the shield / schedule relock.

## iOS behavior diffs adopted vs kept (WriteView comparison)

Adopted: preferences-driven backspace (replaceSuffix) / autocorrect IME
flags / font+size via lazure `writingTextStyle`; registry top-bar lines on
every rejected key; target-countdown timer with remaining/written caption;
unlock state pill; passive quick-pass line; sealing 3-beat flow with veil,
hashLine `Sealed · XXXX...YYYY`, free-target moment, contextual gate button,
`or stay` continuation; `sealIfLeftInMotion` on ON_STOP; free/entitled nudge
split; input-stats sidecar at seal (backspaceCount = rejected backspaces,
enterCount = rejected enters — exactly iOS's counters; allowed deletions
live in the protocol itself, not the stats).

Kept (Android-specific, iOS diverges): dark chamber visuals (white-on-black,
RitualRings, terminal-silence countdown ring, latest-glyph display) — the
lazure retheme of the writing chamber is PARITY WS5's call; clipboard/file
import affordances; continuation back button; AnkyApp-hosted nudge/error
bubbles. The seal-beat visual is an approximation (breathing sun + violet
glow, no sprite/thread-tangle — no sprite assets on Android yet).
