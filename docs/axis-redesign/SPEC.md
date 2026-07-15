# Anky v2 — The Axis Redesign

**Status: ratified July 14, 2026. This spec is authoritative. Where the current codebase disagrees with this document, the codebase changes, not the spec.**

> **Addendum 1 (ratified July 15, 2026) governs above this spec.** See `ADDENDUM-1.md`. Where the addendum conflicts with this document, the addendum wins. It adds: the Anchor's surfacing context on the landing surface (§A1, extends the §2 grammar table); the exact geometry of the opened strata entry — decompress-in-place, sticky header, writing-then-reflection order (§A2, refines §7/§12); unsent-session coexistence with no shame marking (§A3, refines §4/§7); and the ore/glaze voice pair within the lazure register (§A4, extends §10). The Rive→SwiftUI (§5) and melt→crossfade (§7) deviations below are folded in.

Reference images in `./reference/`:
1. `ascent.png` — the send vigil, mid-charge (electric register, thumb pressing spine)
2. `channel-closed.png` — sentinel fired, keyboard fallen, medallion Anchor revealed with filament
3. `reflection.png` — Anky's reflection received (warm lazure, lines descending from faint gold spiral)
4. `landing.png` — landing surface / history strata (dated entries fading with age, ember at base)
5. `writing.png` — the writing session (parchment, keyboard up, cursor at bottom)

---

## 1. Core concept

The app is not a set of screens. It is **one vertical world organized around a single fixed point: the Anchor.**

- The Anchor: small circular element, horizontally centered, ~80–90pt above the bottom edge (inside thumb arc, above the home-indicator gesture zone). Its screen position **never changes, ever.** The app's polar element.
- The Anchor is the app's **only navigation primitive.** No tab bars, nav bars, back buttons, menus.
- Two visual registers:
  - **Lazure** (default): warm translucent watercolor — golden-amber + pale violet washes, paper grain, Fraunces serif, ink-brown text, no pure white/black, no chrome. The human world. (images 3,4,5)
  - **Electric** (transfer only): deep indigo-black, Geshtu interior as X-ray — faint blue wood-grain, luminous spine with **exactly seven stops**, spiral ear at top. Cold, austere. ONLY during the send vigil. (image 1)
- Grammar: **words rise from the Anchor to be heard; days settle around it to be kept.** Cold ascent, warm descent.

## 2. The Anchor — interaction grammar

| Context | Tap | Long press |
|---|---|---|
| Landing surface | Enter writing session | Nothing (no unsent session) |
| Channel closed, unsent session exists | Nothing / soft pulse | **The send vigil (§5)** |
| During ascent/reflection | Suspended | Suspended |

- Empty long-press: at most one faint pulse that drains. The Geshtu does not carry empty offerings.
- Anchor idles with a very slow breathing animation. Never bouncy, badged, or red-dotted.
- **Architecture:** the Anchor lives in AppRoot as a ZStack overlay above the entire view hierarchy. It belongs to no screen. Identical absolute position everywhere — this builds muscle memory.

## 3. Writing session (image 5)

- App **always opens directly into a writing session.** Writing is the front door.
- Keyboard up the whole session and **cannot be manually dismissed.** Only the sentinel drops it (8s without a keystroke → channel closes). Existing 62.5Hz ticker + per-keystroke atomic writes + session-string protocol unchanged.
- The keyboard physically covers the Anchor's position while writing. Intentional and load-bearing: **you cannot send while the channel is open.** The state machine also guarantees this — the Anchor only mounts/activates after the sentinel fires.
- Geometry: the spacebar sits almost exactly where the Anchor lives. Preserve this alignment.

## 4. Channel closes (image 2)

Sentinel fires → keyboard falls → Anchor revealed in its eternal position with a faint vertical filament rising from it. The session's writing rests above on the parchment.

Two options only:
1. **Hold the Anchor** → send vigil (§5)
2. **Scroll / walk away** → session settles unsent into the strata (still saved locally; unsent ≠ lost)

No buttons. No "Send to Anky" label. No dialog.

## 5. The send vigil (image 1)

Long-press-and-hold the Anchor for a sustained duration. **Default 8 seconds** — mirroring the sentinel: channel closes through 8s of absence; writing sends through 8s of presence.

- User-configurable, **hard floor of 3 seconds.** Never below.
- On press: register flips to electric — Geshtu interior, indigo-black, faint grain, seven-stop spine ascending to the spiral ear.
- The **words themselves travel:** session text lifts from its lines, compresses toward the spine axis, climbs. Lowest words brightest/legible; near the crown they thin into filaments drunk by the spiral. The screen does not slide; the writing leaves.
- **Haptic detents:** charge crosses one station ~per second (7 stations over the hold). Each crossing = a small haptic tick, slightly firmer than the last. Arrival at the spiral (sec 8) = a different, softer terminal haptic. Eight beats total.
- **Interruption:** thumb lifts before completion → energy drains fully back down the spine, visibly, slightly faster than it rose. Next attempt starts from zero. No partial credit, no resume. Ever.
- **Restraint is doctrine:** builds like breath deepening, not a weapon charging. NO particle fireworks, NO lens flares, NO screen shake. An X-ray of an offering. If it feels spectacular, dial it down.
- **Implementation (amended by Addendum 1, ratified): SwiftUI-native, not Rive.** One controller drives a `charge` (0→1) from press duration, with release/drain. The 57-frame Anky character does NOT appear here — only the vessel is seen carrying. Acceptance is behavioral, not toolkit-bound: seven escalating haptic detents ~1/sec, a distinct softer terminal beat, a full visible drain on early release, charge monotonic with press duration.
- **Accessibility (non-negotiable):** when assistive settings are active (AssistiveTouch, Switch Control, reduced motion), offer an alternate completion path — reduced hold or press-then-confirm. The ritual is attention, not endurance.

## 6. The reflection (image 3)

On vigil completion, register flips warm. Electric dims; warmth blooms downward from the spiral; a faint gold tracery of the spiral remains at top.

- Anky's reflection **descends:** 4–6 short lines settling top-to-bottom onto the lazure, topmost line slightly more luminous.
- **Voice constraint (canonize in generation prompt):** Anky reflects primarily by returning the writer's own language, first person → second person, confession → blessing ("i stayed" → "you stayed"). Every reflection must contain ≥1 phrase that could ONLY have come from this session's writing. Reject/regenerate generic wellness copy.
- **No reply.** No input field, no chat. The reflection is finite and received. The user's response is tomorrow's writing.
- The Anchor glows softly at the base, at rest.

## 7. The settle → landing surface (image 4)

Scroll past the reflection's last line → the reflection **melts into the strata:** its frame interpolates into one history entry (first line + small date) as the newest layer. No modal dismissal, no push/pop — scroll-driven transformation (SwiftUI `scrollTransition` / scroll-position interpolation). Reflection and landing are one continuous scroll view.

> **Shipped state (Addendum 1, verification Q2):** this is a **disciplined crossfade**, not a true geometric melt. As the reflection block scrolls up it fades, shrinks (~0.86), and blurs while the newest strata stub is revealed beneath in one continuous scroll; the multi-line reflection does not geometrically interpolate into the one-line stub. Ratified as acceptable for this release. A true melt remains a future refinement, not a silent gap.

Landing surface (everything "outside writing"):
- Lazure ground. Anchor at base, breathing. Above it, a single centered column of past sessions: **first line + small date. Nothing else.** Newest at top; entries grow fainter with age, absorbed like sediment strata.
- **Tap an entry** → brightens to full presence, opens to read in full. Memory dims; attention restores.
- **No streaks, no gaps, no counters, no grayed missed days.** The column is made only of presence. Absence is never rendered. Doctrine.
- Empty state (day one): near-bare lazure, Anchor pulsing, one line: `nothing here yet. everything you write will rise.`
- **At the very bottom**, beneath the oldest entry: a single quiet glyph — the **seed**. Opens settings, subscription management, account deletion. The user who scrolls through their whole past arrives at their origin.

From landing, exactly two options: tap Anchor (write) or scroll (remember). At every resting point, ≤2 options, one always the Anchor.

## 8. Deletions

- Delete the **painting screen** entirely.
- Delete the **map** from the landing flow (Sojourn content; may return Aug 1 with kingdom context).
- Delete residual tab/nav chrome, the swipe-left-to-right send gesture, and the "Send to Anky" button/label everywhere.
- Plus (§12): `Map/MapView.swift`, check-in flow files, `YouView`, the reading chamber as a routed destination.

## 9. Onboarding: the rehearsal

Tutorial = the user's first real session, instrumented once:
1. First launch opens into writing (minimal onboarding compressed per existing ~8-screen plan).
2. First channel closes naturally (sentinel). Keyboard falls, Anchor revealed.
3. **One time only:** a quiet line above the Anchor — `hold, and don't let go` — while the Anchor performs a single slow inhale up the first station and back down.
4. They perform the vigil with their own first words. Tutorial and first offering are the same event. Never explained again.

**App Store review hardening:** reviewers won't write long enough to hit the sentinel. Onboarding must reach the reveal quickly/deterministically (e.g. shortened onboarding sentinel) so the long press is discoverable. Build this path explicitly.

## 10. Register/type tokens

- Lazure: golden-amber + pale violet translucent washes, paper grain, Fraunces/serif, ink-brown text, no flat fills, no pure white/black, no chrome.
- Electric: indigo-black ground, cobalt/pale-cyan luminance only, serif italic for traveling words, no warm hues while in this register.
- Spine has **exactly seven stops.** Spiral is the eighth station. Canon (GŠT doctrine); do not add/remove for visual balance.

## 11. Build order

1. Anchor overlay in AppRoot + state machine (mount rules, tap/hold grammar)
2. Landing surface: single scroll view, strata column, fade-by-age, tap-to-brighten, seed glyph
3. Channel-close reveal (keyboard fall → anchor reveal, filament hint)
4. Send vigil: Rive state machine (`charge`/`release`/`drain`), haptic detents, register flip — **build this best; it is the heart**
5. Reflection descent + voice-constraint generation prompt
6. Settle transition (reflection → strata entry)
7. Onboarding rehearsal + review-proof path
8. Deletions and dead-code removal

**Ship criteria:** a person can write, fall silent, hold for eight seconds, receive their own words back warmed, and watch the day take its place among their days — with no button ever labeled anything.

## 12. Reconciliation with the current codebase

"Absorbed" = the function survives, the screen does not.

| Current | Fate |
|---|---|
| `PaintingHomeView` | **Deleted.** Replaced by landing strata (§7). |
| `CheckInFlowView` / `HomeDailyChamberView` | **Deleted.** Intent absorbed by app opening directly into writing. |
| `WriteView` | **Kept as core**, restyled to image 5. Remove quick-settings (config lives at the seed). Keyboard non-dismissable per §3. |
| `AnkyReadingChamber` | **Absorbed by vigil + latency hiding.** Delete as a screen. |
| `RevealView` | **Split in two.** Fresh reflection → §6 (descent, no chrome, no share UI). Copy/share-cards/record → opened strata entry. |
| `AnkyRecordingView` | **Kept.** Reached only from an opened strata entry. |
| `YouView` | **Deleted.** Identity/journey lives at the seed (§7). |
| `ArchiveChamberView` | **Becomes the landing strata** (§7) — likely a rewrite. Opens into full-entry read view (inherits RevealView's share/record). |
| `AnkySettingsView` | **Kept**, via the seed glyph. Keys, iCloud backup, recovery phrase, subscription mgmt, account deletion, vigil-duration setting. |
| `OnboardingView` / `GateSetupView` / `EmergencyBreathView` | **Kept.** Gate/breath mechanic untouched (outside the axis world), except onboarding's final act becomes the rehearsal (§9). EmergencyBreathView must remain reachable exactly as today — safety surface, do not bury. |
| `PaywallView` | **Kept, repositioned** (below). |
| `Map/MapView.swift` | Confirmed legacy/unwired. **Delete the file.** |
| `selectedTab` router in AppRoot | **Replaced** by axis state machine: `writing → channelClosed → vigil → reflection → landing`, plus `entryOpen` and `seed` as landing sub-states. |

### Latency hiding (replaces the reading chamber)

Fire the reflection-generation request **at sentinel-fire** (channel close), not at vigil completion. The session is immutable then, so it's safe even if the user never sends — discard/cache the result for an unsent session per existing privacy posture. The 8-second vigil covers most generation latency. If not ready at arrival: the cooled gold spiral tracery lingers, pulsing slowly, until the first line descends. No spinner, no "Anky is thinking" copy — the ear is simply still listening. Inherits the reading chamber's spirit in ~2s of screen time.

### Paywall placement

Writing is free; the vigil is the paid act.
- Unsubscribed long-press does **not** begin the charge. A quiet lazure sheet rises (paywall, restyled to register — no confetti pricing UI) explaining reflections are the paid practice. Dismissing returns to channel-closed; session settles unsent, never lost.
- **Never** interrupt mid-charge; never let a completed vigil dead-end into a paywall. Two forbidden placements.
- Recommend (flag to Jorge): **first vigil free**, so the rehearsal completes with a real reflection and the paywall is first met on day two, after the full loop is felt once.
