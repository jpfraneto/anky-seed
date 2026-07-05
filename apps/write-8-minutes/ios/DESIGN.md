# DESIGN.md — The Anky Canon

This file is the source of truth for _why_ Anky is the way it is. The app itself is the source of truth for _what_ it currently does. When the two disagree, either the code has drifted or this document has been outgrown — stop and decide which, on purpose. Paste this file into any fresh working session before touching product surfaces.

---

## 1. What Anky is

Anky is a door. On one side is your phone as the world designed it — infinite, loud, engineered to take. On the other side is eight minutes of you, writing, unable to delete and unable to stop. Anky stands at the door and asks you to write with it before you scroll.

It is not a journaling app. Journaling apps store entries. Anky produces _sessions_ — a keystroke-perfect stream of consciousness, sealed with a hash, gone from the surface and permanent underneath. It is not a habit tracker. Habit trackers count. Anky witnesses.

The one-sentence pitch, internally: **you cannot lie at 8 minutes of no-delete writing.** Everything else in the product exists to get a person to that moment and to honor what happens there.

## 2. The invariants (never negotiate these)

- **8 minutes** is the full practice. **8 seconds** of silence ends a session (the `8000` sentinel; deltas cap at `7999ms`, making `8000` the only valid terminal marker). These numbers are constitutional. They predate every screen and will outlive every redesign.
- **No delete, no stop.** The keyboard has no backspace during a session. The timer does not pause. What is written is written.
- **The string IS the session.** Line 1: epoch-ms timestamp, space, first character. Every subsequent line: 4-digit zero-padded delta-ms, space, character. Newlines are literal. SHA-256 of the string goes on-chain. Perfectly deterministic, perfectly reconstructable. No screen may ever misrepresent this.
- **The target is a floor, never a ceiling.** Sessions never cut off at the user's personal target. Anky never truncates writing. Ever.
- **Nothing leaves the phone unsealed.** Writing is encrypted to the enclave's public key or stays local. The backend is blind by design. Every privacy sentence in the UI must remain literally true.
- **Anky grants; the user never loses.** Passes are Anky opening the door, not the user spending lives. Copy that frames the user as failing, spending, or losing is wrong even when it's shorter.

## 3. The philosophy — why Steiner, why lazure

Rudolf Steiner painted classroom walls in _lazure_ — thin translucent washes of pigment, layer over layer, so that a wall never presents a flat dead color but something that breathes, that light moves through. The wall is alive because it doesn't pretend to be finished.

That is the visual and spiritual register of Anky, and it's not decoration. The lazure principle applies to everything:

- **Surfaces breathe.** Backgrounds are washes, not fills. Color arrives in translucent layers (goldLight→gold serif titles, paper body text, madder for the moments of weight). Nothing is flat, nothing is corporate, nothing looks like a productivity app.
- **The writing is lazure too.** A stream-of-consciousness session is thin layers of the self, applied without correction. You don't get to sand it down or repaint. The no-delete rule _is_ the lazure technique applied to language.
- **Anthroposophy's actual bet** — the one we inherit — is that inner life is real, developable, and worth building architecture around. Steiner built schools where the walls served the child's inner development. Anky builds an app where the phone serves the writer's. The phone-blocker isn't a punishment feature; it's the wall of the classroom.
- **The threshold, not the metric.** Steiner education is organized around thresholds (the 8-day gate is ours). We mark crossings — Day 1, first seal, first time past the target — with light and haptic, once, and then we get out of the way. We do not gamify. No streaks-as-anxiety, no leaderboards, no confetti economies.

The night→dawn thread is the canonical expression: on the dark onboarding screens the golden thread is a thin outline; at dawn it becomes filled. Same thread, filling with light. Any new transition in the app should ask itself whether it can read that way — continuity transforming, rather than one thing replaced by another.

## 4. The voice

Anky speaks in the first person and begins doing so at the moment of meeting ("Meet Anky" screen) — never before. Before that moment the app narrates; after it, Anky is present.

Rules of the voice:

- **Short, warm, unhurried.** "Day 1. Write with me." Not "Start your journey!" Anky has been here for four years and is not in a rush.
- **Honest to the mechanism.** Every promise on a screen must be something the code actually keeps. (The 8-day journey screen was written from what `EightDayGateStore` actually tracks. That's the standard.)
- **Exhaustion, not punishment.** When passes run out: "I've opened the door three times today. Write with me first." Anky gets tired; the user doesn't get punished.
- **One privacy line, stated plainly, wherever writing begins:** "Stays on this phone. Nothing you write ever leaves unsealed."
- **Gibberish is met with warmth.** Some sessions are keyboard-mashing at a locked door. The reflection prompts treat that as part of the practice, not a failure of it.

## 5. Straightforwardness — the shape of the flow

The process of getting a user to write must be almost embarrassingly direct. The state of the art in onboarding is manipulation; ours is a contract.

- **The ask lives at the threshold of the gate** — once, honestly, in the light. The paywall is one screen, after the journey map and before Day 1: "Try Anky for $0," three free days that end at the first Daily Unlock, the price at full legibility, a promised reminder before the trial converts (and the reminder is actually sent — it's the trust mechanism, never cut it). Toggling plans changes nothing but the selector and the CTA; declining leaves the screen unchanged. No discounts, no countdowns, no second ask in the same breath. Payment never appears inside the writing itself, and sealed words are always readable, subscribed or not.

- **Name the problem, do the math, offer the deal.** Hours on the phone → years of a waking life → "two novels' worth of yourself." Then the mechanism, then "Deal." No dark patterns, no fake scarcity, no rating beg. (The single requestReview fires once, after the first sealed session settles — and skips if they bounce. One shot, spent where there's actually something to review.)
- **One typing moment in onboarding** (the name), and it's optional. Everything else is a tap. Friction is spent only where it buys meaning.
- **The keyboard is already rising** when the Day 1 threshold overlay appears. The distance between "I'm ready" and _writing_ should be measured in milliseconds. Every screen between a person and the blank page must justify itself or die.
- **Denial paths never trap.** Notification denied → one quiet Settings line, then continue. Screen Time denied → gate-off state with a gentle setup card on home. No re-prompt loops, no blocking. The door is offered, never forced.

## 6. Freedom — the user chooses their own trip

This is the deepest product decision and the easiest one to erode by accident, so it gets its own section.

**Anky sets the destination; the user sets the pace.** Eight minutes is the practice — it's anchored visibly at the end of the slider, it's in the name of everything, it is where this goes. But the _daily target_ is the user's: 1 to 8 minutes, chosen in onboarding, changeable, theirs. A one-minute writer is not a lesser member of this practice. They are a person at minute one.

Consequences that must hold everywhere:

- The target **never** truncates a session (floor, not ceiling — repeated here because it will be threatened repeatedly).
- The two tiers stay two: **Quick Pass** (one sentence → ~15-minute unblock, 3/day, reset at local midnight) and **Daily Unlock** (write to your own target → the rest of the day). No third tier returns. The old three-tier system died for good reasons: complexity is a tax on the threshold. _(Amended July 2026, phase 3: the Daily Unlock belongs to the subscription. Quick Passes and the emergency breath are everyone's forever — protection is never revoked for non-payment — and a free writer at their target still earns a Quick Pass. The tiers are still two; one of them is now part of the deepening.)_
- Day 7 of the gate — writing _past_ your target — is an invitation upward, and the only one. Progression is offered as a threshold, never enforced as a nag.
- The user can always choose the shallow door (Quick Pass) without shame in the copy. Freedom includes the freedom to not go deep today.

The trip metaphor is literal in the lore: eight kingdoms, sojourn cycles, a path. But paths in Anky are walked, not dragged along. Any feature that moves the user without their hand on the door is off-canon.

## 7. Design language quick reference

- **Pigments:** lazure washes; gold/goldLight (thresholds, thread, titles), paper (body), madder (weight/serif emphasis), ink serif for the journey map, night surfaces for pre-dawn onboarding.
- **The thread:** thin gold outline on night, filled `ThreadButtonStyle` at dawn and after. One visual grammar for "the way forward."
- **Haptics:** one soft haptic per deliberate CTA; success+medium reserved for true thresholds (Day 1 crossing, seals). Haptics are punctuation, not applause.
- **Motion:** crossfades over ~1.2s for world-changes (night image → breathing lazure wall), staggered beats for revelations (the math screen). Nothing snaps; nothing bounces.
- **Typography:** serif for what Anky says and for weight; the writing surface itself stays utterly plain — the user's words need no costume.

## 8. What is noise

To keep this document honest, the anti-canon: pixel-perfect Figma files maintained "in sync" with shipped code; streak-guilt mechanics; a third unlock tier; paywalls inside the writing itself, or any paywall theatrics — countdown timers, panic discounts, plan-toggle bait, fine-print pricing; any analytics beyond what a decision needs (current standard: one UserDefaults int for onboarding drop-off); any copy Anky wouldn't say out loud, slowly, to a friend at a locked door.

(Amended July 2026: the original canon said "no paywall in onboarding." We changed our mind on purpose — the ask moved to the gate's threshold because asking mid-ritual, in plain terms, is more honest than ambushing after it. The manner of asking is the invariant now, not the absence of the ask.)

(Amended July 2026, phase 3: the free tier is the door without the deepening. Protection — gate, shield, Quick Passes, emergency breath — is never revoked for non-payment, and seconds always count, for everyone, forever. What the subscription opens: reflections, paintings beyond the first ceremony, the journey map, and the Daily Unlock. Everything gated is shown gently under a veil — a parchment mist and a spiral, one tap from the ask — reading as *not yet*, never as *denied*. There is no lapsed lockout screen; a lapse is a narrowing, not a death. Anky-initiated paywall pressure is capped at once per rolling week across all surfaces; a writer tapping a veil is always answered.)

---

_The wall is painted in layers. So is the app. Add your layer thin, and let the light through._
