# Axis Redesign — Progress

**Branch:** `axis-redesign` (pushed to origin). **Status: 7½ of 8 phases done.**

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
