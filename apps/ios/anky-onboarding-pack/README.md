# Anky Onboarding Animatic — Implementation Pack

Hand this directory to Claude Code inside the Anky iOS repo. Read this file fully, then TIMELINE.json, then skim reference/animatic_v1.html (open it in a browser to *feel* the target — it is the approved reference cut, not decoration).

## What this is

Anky v2.0.0's first-launch onboarding: a ~21-second wordless animatic that plays once, before anything else, and hands the user directly into the name-entry screen. It replaces whatever onboarding intro currently sits before name entry. Nine still frames animated with crossfades and slow zooms (Ken Burns), one hard cut, a carve-reveal effect, a dissolve to the lazure ground, and a typed question. No audio. No text except the final question.

The story: a blank wooden tablet. Blue hands cradle it. A knife carves "anky" into it, stroke by stroke. HARD CUT — the same tablet, now ancient and black with millennia of writing, still in the same being's hands. The being looks up, sees the user, smiles. It carves a fresh blank tablet — a gift. Offers it to the camera. Push into the blank wood. Return to the opening frame: blank wood, waiting. The wood dissolves into the white lazure watercolor ground of the app, and the question types itself in halting rhythm: "what should i call you?" The keyboard rises. That question screen is the app's real name-entry screen — the video does not end, it *becomes* the app.

## Non-negotiable constraints

1. **The handoff is pixel-identical.** The final state of the animatic IS the shipped name-entry screen — same Fraunces question, same layout, same background. Architecture must guarantee this by construction, not by imitation: render the real NameEntryView underneath the animatic's final frames and fade the animatic layer away (see Architecture). If the animatic ends on a lookalike and then swaps views, the implementation is wrong.
2. **The time cut at 8.6s is a hard cut.** Zero crossfade. TIMELINE.json marks it. Do not soften it.
3. **Beat 6 (gift carving) is the longest hold.** Do not rebalance timings to feel "snappier."
4. **Works fully muted / has no audio.**
5. **First launch only.** Persist a flag (alongside existing first-run state; the app already distinguishes fresh installs via seed-phrase creation flow). Never replay on update or reinstall-with-restored-identity.
6. **Skippable.** A quiet "skip" affordance (bottom-right, low-contrast, Fraunces lowercase) appears at 3.0s. Skip jumps straight to the finished name-entry state (question fully typed, keyboard up). App Review is unforgiving about forced intros.
7. **Reduce Motion:** if UIAccessibility.isReduceMotionEnabled, skip the animatic entirely and land on name entry with a simple 400ms fade. No parallax, no zooms for these users.
8. **Typing rhythm is data, not polish.** The per-character delays in TIMELINE.json are the anky protocol's halting rhythm. Use them verbatim. Same for the carve-reveal steps.

## Architecture (SwiftUI)

Single new module: `Onboarding/`

- `OnboardingAnimaticView.swift` — full-screen ZStack. Layers bottom-to-top: (a) the real `NameEntryView`, alive but non-interactive until handoff; (b) the lazure dissolve is simply the animatic layer's opacity going to 0 over 2.1s, revealing (a); (c) `AnimaticStage` — the nine beat layers; (d) skip button.
- `AnimaticStage.swift` — renders beats from `AnimaticTimeline`. Each beat: an `Image` in a `GeometryReader`, aspect-fill, `scaleEffect` animated linearly from `scale_from` to `scale_to` over the beat duration (+600ms tail), anchored per TIMELINE.json `anchor` (use `UnitPoint`). Crossfades via opacity with the beat's `fade_in_ms`; the hard cut is `fade_in_ms == 0` → no animation, instant opacity.
- `AnimaticTimeline.swift` — decodes TIMELINE.json (bundle it as a resource; do NOT transcribe numbers into code — the JSON is the single source of truth and will be tuned).
- `CarveRevealView.swift` — beat 3. Two images stacked: `03a_carve_pre` below, `03b_carve_post` above, the top one masked by a rectangle whose width animates through the `carve_reveal.steps` fractions (each step: 140ms easeOut, then hold until next step). Mask the full image height — the images are identical outside the word region, so a full-height sweep is invisible except where the letters live.
- `TypedQuestionView` — only if NameEntryView doesn't already own its question label. Preferred: add an optional "typewriter" entrance to the existing question label in NameEntryView, driven by the delays array, ending by focusing the real TextField (keyboard rises itself — never mock the keyboard).
- Driver: a single `Task` with `try await Task.sleep` per scheduled event, or TimelineView — either is fine, but all events must derive from one t0 so drift can't accumulate. Cancel cleanly on skip.

Integration point: wherever the app currently decides "fresh install → show name entry," it now shows `OnboardingAnimaticView` instead, which itself contains NameEntryView. Everything after name entry (first writing session, then paywall) is untouched — the paywall stays AFTER the first writing session.

## Assets

`assets/` holds the nine approved frames at generation resolution (~1024×1536). Ship them in an asset catalog. They must be preloaded/decoded before t0 — first frame must render instantly on cold launch (decode off-main during app init, or use `Image(uiImage:)` with pre-decoded UIImages). Total ~23MB of PNG; converting to HEIC in the catalog is encouraged if quality holds — check the lazure grain doesn't band, especially the dark temple backgrounds of beats 4–7.

`03a_carve_pre.png` is a programmatic clone-stamp (word removed) — adequate under motion. If it looks patchy on device at beat 3's zoom level, flag it and continue; a regenerated clean plate can be swapped in later without code changes.

`08_pushin.png` is lower resolution (552×870) and beat 8 zooms to 1.42 — watch for softness on device. Acceptable for v1; flag if ugly.

## Acceptance criteria

Run on a physical iPhone, cold launch, fresh install:

1. Animatic starts within 300ms of first frame availability; no white flash, no placeholder.
2. The 8.6s cut is instantaneous; every other transition is a crossfade.
3. Letters of "anky" appear in visibly halting groups, not a smooth wipe.
4. The dissolve reveals the *live* name screen; question types in the given rhythm; the real keyboard rises; the user can type their name immediately with zero visual discontinuity — recording a screen capture and stepping through the handoff frame-by-frame shows no layout jump.
5. Skip at any point ≥3s lands on the completed name screen in <500ms.
6. Reduce Motion path verified.
7. Kill/relaunch mid-animatic: animatic restarts from 0 (it's 21 seconds; resume logic is over-engineering).
8. After name submission, flag persists; animatic never plays again.

## What NOT to do

- Do not "improve" timings, easings, or beat order. The reference HTML is the approved cut; deviations require sign-off.
- Do not add narration, captions, sound, haptics, or a progress bar.
- Do not mock the keyboard or the name screen.
- Do not gate the animatic on network, auth, or RevenueCat state — it must play offline on airplane mode.
- Do not touch the writing screen, the 62.5Hz ticker, or anything downstream of name entry.

## Open question for the human (ask before implementing if unclear)

The current 57-frame PNG Anky character in-app vs. the animatic's rendering of Anky differ in style. This was flagged and accepted for v1 — the animatic is canon-forward. If during integration you find a place where both appear on screen simultaneously, stop and ask.
