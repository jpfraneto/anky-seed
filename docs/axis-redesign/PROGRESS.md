# Axis Redesign — Progress

**Branch:** `axis-redesign` (pushed to origin). **Status: 7½ of 8 phases done; Addendum 1 (A1–A4) landed.**

Everything is built behind the flag `AppRoot.axisWorldEnabled` (currently `false`),
so **the shipping app is completely untouched**. Flip the flag to `true` to run the
axis world (it replaces `AppRoot.body` entirely). A DEBUG phase-stepper across the
top lets you walk every phase.

All new axis code lives in `apps/ios/Anky/Features/Axis/`. Spec + reference images
are in `docs/axis-redesign/`.

## What's done (each committed, compiled, screenshot-verified on the simulator)

| Phase | What landed | Files |
|---|---|---|
| **1 — State machine + Anchor** | `AxisState` (the phase machine that replaces the `selectedTab`/`writeSurface` router) and the fixed breathing medallion overlay + rising filament, at its eternal position ~86pt above the bottom. | `AxisState.swift`, `AnchorView.swift`, `AxisWorldView.swift` |
| **2 — Landing strata** | The fading column of past days (first line + date, newest on top, fading with age), the seed glyph at the bottom. Matches `reference/landing.png`. | `LandingStrataView.swift` |
| **3 — Channel-close reveal** | The real `WriteView` in a new `axisMode` (clean parchment, no chrome). On seal the keyboard falls and the Anchor is revealed; the sealed writing rests above (`ChannelClosedView`). Reuses the existing 8s sentinel + atomic-write engine untouched. | `WriteView.swift` (`axisMode`), `AxisWorldView.swift` |
| **4 — The send vigil** *(the heart)* | SwiftUI-native. `VigilController`: one continuous press → charge 0→1, seven escalating haptic detents + a soft terminal beat, drain on early release. `VigilView`: the electric register — luminous seven-stop spine, spiral ear, the writing traveling upward. Matches `reference/ascent.png`. | `VigilController.swift`, `VigilView.swift` |
| **5 — Reflection descent** | The blessing descent (4–6 short lines, the writer's own words, 1st→2nd person). Generation fires at the sentinel to hide latency under the vigil. New backend `PROMPT_AXIS`, routed by an `X-Anky-Surface: axis` header. Matches `reference/reflection.png`. | `ReflectionDescentView.swift`; `backend/reflection.ts`, `backend/server.ts`; `MirrorClient.swift`, `RevealViewModel.swift` |
| **6 — Settle transition** | Reflection and strata as one continuous scroll; scrolling melts the reflection into the newest strata entry (`scrollTransition`). | `ReflectionDescentView.swift` (`ReflectionSettleView`), `LandingStrataView.swift` (`StrataColumn`) |
| **7 — Onboarding rehearsal** | The tutorial IS the first session: a one-time "hold, and don't let go" hint + the Anchor's single inhale at the first channel-close, a 4s review-proof sentinel, first vigil free so it ends on a real reflection. | `AxisWorldView.swift`, `WriteViewModel.swift` (`terminalSilenceOverrideMs`) |
| **8a — Gating + folded sheets** | Writing is free; the vigil is the paid act. First vigil free, then an unentitled hold raises the paywall sheet (never mid-charge). The seed opens the real `AnkySettingsView` + gate setup. | `AxisWorldView.swift`, `AnchorView.swift` |

## Addendum 1 (A1–A4) — landed (each committed, compiled, screenshot-verified)

Ratified `ADDENDUM-1.md`; SPEC.md amended in the same pass (Addendum-1 pointer
at top, §5 Rive→SwiftUI, §7 melt→crossfade). Still all behind
`axisWorldEnabled=false`; **8b not started.**

| Section | What landed | Files |
|---|---|---|
| **A1 — the Anchor surfaces to now** | On the landing surface the Anchor's tap resolves by scroll position: at the living edge → write; scrolled deep → **surface to now** (a fast spring with slight overshoot, not `scrollTo(0)`); entry open → close then surface. Surfacing and writing are never chained. `landingAtTop` (tolerance ~½ screen, O(1) scroll sentinel) + `surfaceTick` added to `AxisState`. | `AxisState.swift`, `AnchorView.swift`, `LandingStrataView.swift`, `AxisDebugSeed.swift` (new) |
| **A2 — opened entry decompresses in place** | Tapping a stub expands the day inline in the column (no pushed screen/sheet/modal), neighbours pushed apart. Writing first (in full), a quiet seam, then the reflection — reached only by scrolling; never separately addressable. Sticky date header (tap to close); one day open at a time. `share`/`record` affordances after the reflection; `AnkyRecordingView` + `ShareCardPreviewView` reached here. | `LandingStrataView.swift`, `AxisWorldView.swift`, `RevealView.swift` (`ShareCardPreviewView` → internal) |
| **A3 — unsent sessions coexist** | Column makes no sent/unsent distinction (no badge/dimming/copy). Opened unsent day = writing only. Retroactive send out of scope. **Closed the Q4 leak:** the sentinel-fired reflection is now held in memory and committed to the store only when the vigil sends; walking away discards it, never persisted. | `RevealViewModel.swift` (`persistsReflection` + `persistPendingReflection()`), `ReflectionDescentView.swift` (`commit()`/`discard()`), `AxisWorldView.swift` |
| **A4 — ore & glaze** | Two voices in the lazure register as named tokens. Ore: Fraunces regular, smaller, tighter, grayer ink (`ankyOre`) — the sealed writing + opened-entry writing. Glaze: Fraunces italic, more luminous ink (`ankyGlaze`), looser leading — the §6 descent + opened-entry reflection. Never labelled. | `AnkyLazure.swift` (`ankyOre`/`ankyGlaze`), `AxisVoices.swift` (new, `.oreVoice()`/`.glazeVoice()`), `AxisWorldView.swift`, `LandingStrataView.swift`, `ReflectionDescentView.swift` |

Plus verification hardening: Q1 `TODO(server-reconcile)` on the free-vigil flag,
Q3 `.ignoresSafeArea(.keyboard)` on the Anchor overlay.

**Verification method note.** This pass was verified by building the `Anky`
scheme (Debug, iPhone 16 Pro sim) green for every section and screenshotting the
real surfaces via a DEBUG launch-env harness (`SIMCTL_CHILD_AXIS_DEBUG_SEED` /
`_PHASE` / `_OPEN_FIRST` / `_OPEN_UNSENT`) that seeds synthetic strata into the
real stores. This environment has **no tap/press/scroll injection** (no idb, no
`simctl` tap, AppleScript assistive-access denied), so purely interactive
behaviours — the surface-to-now gesture end-to-end, the physical vigil hold, the
scroll-driven settle — are verified by construction and static state-machine
reasoning, not by driving the gesture. They remain on the on-device validation
list below.

## Answers (Addendum 1 verification questions)

1. **Free-vigil tracking — device-side; TODO added.** Consumption is
   `@AppStorage("anky.axisFirstVigilUsed")` in `AxisWorldView` → `UserDefaults`,
   i.e. **per-install, not per-account.** A reinstall (or a new device) grants a
   second free vigil. Left as-is for this flagged-off pass with an explicit
   `TODO(server-reconcile)` at the declaration: before ship it must key to
   account identity (RevenueCat `appUserID` or wallet address) reconciled
   server-side. The paid gate itself is already account-scoped via
   `EntitlementStore` (RevenueCat); only the *free-first-vigil* grant is
   device-local.

2. **Settle transition — crossfade, not a true melt.** `ReflectionSettleView`
   applies `scrollTransition(.interactive)` that fades + scales (~0.86) + blurs
   the whole reflection block as it scrolls up, revealing the newest stub
   beneath. The multi-line reflection does **not** geometrically interpolate
   into the one-line stub. This is the disciplined crossfade the addendum
   permits; recorded in SPEC §7. Unchanged by this pass.

3. **Anchor vs. keyboard — now explicitly keyboard-safe.** The Anchor lives in
   `AxisWorldView`'s ZStack overlay (in the axis world, `AxisWorldView` replaces
   `AppRoot.body` entirely). Two things hold its position: (a) it is **hidden
   during `.writing`** (`anchorIsVisible = phase != .writing`), so it never
   coexists with the writing keyboard — the §3 "keyboard covers the Anchor" is
   realised as the state-machine guarantee, not a literal overlap; (b) this pass
   added `.ignoresSafeArea(.keyboard, edges: .bottom)` to `AnchorView` so any
   keyboard (e.g. inside the seed/settings) can never lift it from its fixed
   base. Its absolute screen position is now inset-independent. Verified by
   construction; not driven with a live keyboard (no input injection here).

4. **Latency hiding — confirmed, and the unsent leak is closed.** The reflection
   request fires at **sentinel-close**: `AxisState.channelDidClose` → phase
   `.channelClosed` → `AxisWorldView.onChange` → `AxisReflectionCoordinator.begin`
   → `RevealViewModel.askAnkyForSealedSession`, so generation runs under the
   vigil. Previously that path persisted the result to `ReflectionStore`
   unconditionally on arrival — an **unsent** session's reflection would land on
   disk and attach to its entry. A3 fixed this: the axis vm runs with
   `persistsReflection=false` (held in memory only); `commit()` persists it
   **only** on vigil completion (`.reflection`); `discard()` (walk-away / new
   session) drops it without ever writing it. A never-sent reflection is now
   never attached as if received.

5. **Accessibility vigil path — it exists.** `AnchorView` provides both required
   affordances: (a) `effectiveVigilDuration` shortens the hold to ≤3s when
   `reduceMotion`, Switch Control, or VoiceOver is active; (b) a custom
   `accessibilityAction(named: "Send to Anky")` completes the offering directly
   (`beginVigil()` → `vigilCompleted()`) with no sustained hold at all. So the
   ritual is reachable as reduced-hold **and** as a single activation under
   assistive settings. No new work needed; located in `AnchorView.swift`.

6. **Surfacing performance — no per-stratum work; 500-entry render clean.**
   Seeded 500 entries (`AXIS_DEBUG_SEED=bulk`) and the landing renders
   immediately with no hang. By construction, surface-to-now cannot fire
   per-stratum work for entries it passes: `StrataEntryRow` has **no**
   `onAppear` and **no** `scrollTransition`; the column is a `LazyVStack`
   (rows lazily materialised); `proxy.scrollTo(topID)` jumps rather than walking
   each intermediate row's lifecycle; and the only scroll observer is a single
   O(1) background sentinel measuring the column's top offset. The one caveat I
   could not measure without input injection is the *animated* scroll's
   intermediate frames on device — flagged for on-device validation. (Note: the
   Section-pinned sticky header only exists while an entry is open, not during
   surfacing.)

## What's NOT done — Phase 8b (going live), held on purpose

8b makes the axis the shipping app and is hard to reverse. **It's held until the full
loop is validated on a device against the real backend.** Checklist:

- Delete `PaintingHomeView`, `CheckInFlowView`, `YouView`, `Map/Map*.swift`.
- Remove the `selectedTab`/`writeSurface` router and `legacyBody`; remove the flag + DEBUG stepper.
- **Reconcile the Screen-Time shield → `EmergencyBreathView` / write-before-scroll routing with the axis** (today that lives in `AppRoot`, which the axis bypasses when live — the safety surface must stay reachable).
- Wire the compressed pre-writing onboarding screens into the axis first-run.
- Add a vigil-duration control to the seed.
- Fix `JourneyAnchorTests` path references.

## Recommended next step

Run the branch on a device (set `axisWorldEnabled = true`), walk the real loop once —
**write → fall silent → hold 8s → receive your words → scroll to settle** — with the live
backend. Confirm the vigil haptics/timing and the blessing reflection feel right, and
whether **first-vigil-free** is the behavior you want. Then give the go-ahead and 8b
ships as a clean final commit.
