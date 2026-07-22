# Geshtu v2 — QA Handoff

Branch: `geshtu-v2`. App version: **2.0.0 (56)**. Build target: iPhone 16 Pro
simulator verified green; haptics/gesture surfaces are **device-only** (call
those out — the simulator cannot hold a long-press or render CoreHaptics).

This document is honest about what is **landed and verifiable**, what is
**device-only**, and what is **staged with a written plan** (see `DEVIATIONS.md`
for the why of every staged item). Read `DEVIATIONS.md` alongside this.

---

## 0. State of the branch at handoff

Every commit on this branch compiles; the Swift-package test suites
(`AnkyWriterTests`, `WriteBeforeScrollTests`, `StorageTests`) are green. The app
target builds clean on the simulator.

Commits, in order:
1. `Geshtu D1` — `geshtuWorldEnabled=false`; legacy route canonical.
2. `Geshtu D3` (core) — silence threshold decoupled from the fixed `8000` seal
   sentinel; one 3–30s clamp.
3. `Geshtu D3` (settings) — silence-duration slider in Settings.
4. `Geshtu D2` — the Axis world extracted/renamed in place to `Features/Geshtu/`;
   version → 2.0.0(56); "loading" strings rewritten.
5. `Geshtu haptics` — CoreHaptics ascent score with UIKit fallback.

The Geshtu world itself is **present and compiling but gated off**
(`AppRoot.geshtuWorldEnabled = false`), so the shipping app still runs the
legacy route. To QA the Geshtu world, flip that flag to `true` and run on a
**device** (see §3).

---

## 1. Landed & verifiable in the simulator

### 1a. D3 — silence duration is a setting; the sentinel is a fixed symbol
- **Settings → "The silence that closes the channel"**: a slider, 3s–30s,
  default 8s. Drag and release; the number updates; the value persists across
  relaunch (`WritingPreferencesStore`, standard UserDefaults).
- **Verify the decoupling**: the protocol's end sentinel is always the canonical
  `8000` token regardless of the slider (unit-tested in `AnkyWriterTests`).
  Changing the silence setting must **not** change what a sealed `.anky` writes
  as its terminal marker.
- Test matrix: set silence to 3s, 8s, 30s; in each case the writing surface's
  inactivity-to-close timing should track the setting (device: watch the glyph
  pigment / close timing), and a sealed session still reads as sealed.

### 1b. D12 — version & copy
- **Settings → About / build info**: version reads **2.0.0 (56)**.
- **Paywall & Settings subscription rows**: no literal "Loading…" copy; the
  price/plan waiting states now read "settling in…". Trigger by opening the
  paywall before StoreKit packages resolve (slow network / fresh launch).

### 1c. Regression guard — legacy route unchanged
Because `geshtuWorldEnabled=false`, the entire legacy flow (write → seal →
slide-to-reflect → reading → gate/paintings/you) is untouched and should behave
exactly as 1.3.0 did. Smoke-test one full legacy session to confirm no
regression from the extraction/rename.

---

## 2. Device-only (cannot be verified in the simulator)

### 2a. CoreHaptics ascent score (`GeshtuHapticScore` in VigilController.swift)
On a physical device, inside the Geshtu send vigil (§3):
- **Ascent hum**: a *continuous* haptic that swells in intensity and sharpness
  as the charge climbs the spine (0→1). It should feel like the object filling,
  distinct from the discrete ticks.
- **Eight crossings**: eight escalating UIKit transients as the charge passes
  1/8…7/8 and completes — each firmer than the last.
- **Bloom**: a soft warm transient+swell when the offering reaches the crown
  (`complete()`).
- **Fallback**: on a device with CoreHaptics disabled/unavailable, the eight
  UIKit crossings + terminal beat must still fire (the continuous hum simply
  goes silent). Test with haptics off in Settings → Sounds & Haptics.
- **Early release**: lifting mid-charge drains the charge and **stops** the hum
  (`endAscent()` on drain); no partial credit.

### 2b. The long-press vigil gesture
The simulator cannot hold a press. On device, in the Geshtu world: press-and-hold
the Anchor at a closed channel to run the ascent; release early to drain; hold to
completion to send.

### 2c. VoiceOver / assistive direct-action
With VoiceOver or Switch Control on, the Anchor exposes a **"Send to Anky"**
custom action that completes the vigil without the hold, and the required hold is
shortened (≤3s) when Reduce Motion / VoiceOver / Switch Control is active
(`AnchorView.effectiveVigilDuration`). Verify the direct action sends, and that
Reduce Motion stills the breathing animations.

---

## 3. How to QA the Geshtu world (behind the flag)

1. In `Anky/AppRoot.swift`, set `private let geshtuWorldEnabled = true`.
2. Build to a **device** (haptics + long-press are device-only).
3. Flow: launch → writing surface (keyboard up) → write, then stop; after the
   configured silence the channel closes, keyboard falls, the Anchor is revealed
   with a filament → press-and-hold the Anchor → the register goes x-ray, the
   spine lights, the writing climbs to the spiral crown as the charge fills →
   hold to completion → the reflection descends warm onto the surface → scroll
   to its end → walk away / tap to settle into the strata.
4. Reflection is fired at channel-close (before the press) and only *committed*
   on a completed vigil — an early release keeps the request in flight but never
   persists it (matches D9's "early release does not cancel the request").

> Note: the Geshtu world is the extracted former Axis world; it was a working
> vertical experience on the source branch. It is gated off by default so the
> shipping route stays the verified-stable legacy one (D1). Flipping the flag is
> the QA/dogfood switch.

---

## 4. Staged — NOT in this build (see DEVIATIONS.md for the why)

These are documented with concrete plans, deliberately not landed so the build
and the shield stay green at every commit:

- **D4 — 60-second mission + pause/resume/melt state machine.** The unified
  mission *read* and the settings *control* exist; re-basing `DailyTargetStore`
  from minutes to a 60-second default touches the App-Group shield extension and
  the adaptive-target policy and is staged. The pause/resume/melt lifecycle on
  `ActiveDraftStore` is designed (the store already keys recoverability on the
  absence of the `8000` sentinel) but not yet wired.
- **D9 — full reflection-on-surface replacing the reading chamber, with
  cool/retry.** The Geshtu world already renders the reflection via the reused
  `RevealViewModel` pipeline; wholesale removal of `AnkyReadingChamber` /
  `SlideToReflect` from the *legacy* route, and the terminal-error cool-to-rest
  retry affordance, are staged.
- **D11 — native opening scene + GeshtuCreationStore.** Not started.
- **D7/D12 — mass deletion of Journey/paintings/stats/onboarding + Axis-route
  removal.** This is a cascading refactor of the 3000-line AppRoot and several
  *preserved* surfaces (LevelSyncClient does account-deletion + subscription
  identify; AnkySpriteView/AnkyWitnessView feed Reveal/You/EmergencyBreath;
  AnkyverseCalendar is load-bearing for the preserved SessionIndexStore). It is
  staged so it does not land as a large red diff.

---

## 5. Full device test script (once the Geshtu world is enabled)

Run each on a physical device unless noted:

1. **Fresh install** → writing surface opens keyboard-up; write; stop; channel
   closes after the configured silence; Anchor + filament appear.
2. **Silence setting** (sim OK for the timing): set 3s / 8s / 30s in Settings;
   confirm the close timing tracks each.
3. **Send vigil** → hold to completion; feel the ascent hum + 8 crossings +
   bloom; reflection descends and is scrollable to its end.
4. **Early release at each stage** → arming (tap = soft pulse, no x-ray),
   mid-charge (drains, hum stops, returns to closed channel), near-complete.
5. **Slow network** → the crown gathers/pulses with no spinner and no
   "loading/reading/thinking" copy until the reply lands.
6. **Terminal reflection error** → object cools to rest with a quiet retry (D9,
   staged — verify once landed).
7. **Free / lapsed user** → the vigil press raises the existing PaywallSheet, and
   nothing is sent unless they subscribe (D8; wired via `vigilAllowed`).
8. **VoiceOver / Reduce Motion / haptics-off** → per §2c/§2a.
9. **Legacy regression** (flag off) → one full legacy session behaves as 1.3.0.

---

## 6. Where the seams are

- Charge/press/drain + CoreHaptics: `Features/Geshtu/VigilController.swift`
  (`GeshtuHapticScore` at the bottom).
- Spine / eight crossings / traveling words / x-ray grain: `VigilView.swift`.
- Root button, long-press gesture, accessibility direct-action: `AnchorView.swift`.
- Phase machine + write/reflection transitions: `GeshtuState.swift`.
- Reflection fire-at-close / commit-on-send: `ReflectionDescentView.swift`
  (`GeshtuReflectionCoordinator`) — reuses `RevealViewModel` untouched.
- Composition root wiring the pipeline: `GeshtuWorldView.swift`.
- Silence setting: `Core/Protocol/AnkyDuration.swift` (clamp + canonical token),
  `Core/Storage/WritingPreferencesStore.swift`, `Features/Settings/AnkySettingsView.swift`.
- The flag: `AppRoot.swift` → `geshtuWorldEnabled`.
