# App Store screenshots

> **Status, 2026-08-27 — partially parked.** Scenes 03 (reflection), 04 (archive)
> and 05 (recording) generate correctly in all six locales. Scenes 01 and 02
> need a software keyboard the simulator will not raise; the app refuses to be
> photographed without one, so those two are skipped rather than shipped wrong.
> The existing English App Store screenshots stand until this is picked up
> again. See "The keyboard" below for exactly where the investigation stopped.
> None of this affects a release build — every line of screenshot mode is
> `#if DEBUG` and behind a launch argument.


Deterministic, localized marketing screenshots for Anky iOS — captured from the
real running app, not mocked up.

```bash
cd apps/ios
./scripts/generate-app-store-screenshots.sh
```

That one command validates prerequisites, assembles the fixtures, builds the
app, boots a 6.9-inch simulator, captures 5 scenes × 6 locales, composes the
marketing frames, validates every file, and writes `manifest.json`.

Output lands in `final/<app-store-locale>/` — those are the files you upload.

## What gets made

| # | Scene | Surface | Shows |
|---|-------|---------|-------|
| 01 | `ritual` | `.writing` | Live writing, keyboard up, clock at 7:22 |
| 02 | `simplicity` | `.writing` | A short fragment on a spacious page, clock at 7:41 |
| 03 | `reflection` | `.entryOpen` | A completed writing with Anky's reflection under it |
| 04 | `archive` | `.landing` | The search field and twelve real days |
| 05 | `recording` | `.entryOpen` + camera | A take in progress over a finished writing |

Six locales, from the app's own `knownRegions`: `en-US`, `es-MX`, `fr-FR`,
`de-DE`, `hi`, `zh-Hans`. 30 images at 1320 × 2868, PNG, no alpha channel.

## How determinism is achieved

The app stages each scene itself. There is no UI automation — nothing types a
writing character by character or waits on a hittable element, because that is
the part of a screenshot pipeline that rots.

Instead `-ANKY_SCREENSHOT_MODE YES -ANKY_SCREENSHOT_SCENE <scene>` makes the app
wipe its stores, seed them from a bundled fixture, park the state machine on the
right phase, and write a signal file when the frame has settled. The capture
script waits for that file rather than sleeping and hoping.

Two details worth knowing:

- **The clock is real, and frozen.** The writing scenes go in through the app's
  own draft-recovery path, which restores a session frozen with its ticker
  cancelled. The clock reads the fixture's elapsed time, and the eight-second
  silence sentinel cannot fire and close the channel mid-capture.
- **Dates are fixed, not relative.** Archive rows come from absolute dates in
  the fixtures, so regenerating the set next month produces identical rows.

Screenshot mode is wrapped in `#if DEBUG` *and* gated behind an explicit launch
argument. An ordinary launch — debug or release — never reaches a line of it.

## The keyboard (scenes 01 and 02)

This is the fragile part of the whole pipeline, so it is worth knowing how it
works. iOS shows the software keyboard only when it believes no hardware
keyboard is attached. On a simulator that is governed by
`ConnectHardwareKeyboard`, a **Simulator.app** preference stored per device
inside a `DevicePreferences` dictionary keyed by UDID. Two things follow:

- The top-level `ConnectHardwareKeyboard` default does nothing.
- A purely headless `simctl boot` gives no keyboard either — nobody is around
  to honour the preference.

So the script quits Simulator.app, writes the per-device preference, and
reopens Simulator.app onto the device. If the keyboard still does not appear it
sends ⇧⌘K (Simulator's own I/O ▸ Keyboard ▸ Connect Hardware Keyboard toggle)
via AppleScript and retries the scene once. That needs Accessibility permission
for whatever is running the script — grant it in System Settings ▸ Privacy &
Security ▸ Accessibility if you see the retry fail.

**The app refuses to be photographed without a keyboard.** Scenes 01 and 02 do
not signal ready until `keyboardDidShowNotification` has fired, so a keyboardless
frame cannot be captured silently. On failure the run stops at the first locale
and writes `keyboard-diagnostics.txt` and `keyboard-diagnostic-frame.png` next
to this README, including what the app itself could see — whether the text view
ever took first responder, and whether a keyboard window exists at all. That
distinguishes an app bug from a simulator configuration problem.

Fast loop while debugging this:

```bash
./scripts/generate-app-store-screenshots.sh --locale en-US --scene ritual
```

## Editing the content

Per-locale content lives in `fixtures/<locale>.json`: two writings-in-progress,
one completed writing with its reflection, eleven more archive days, and the
five marketing headlines. Each locale was written in its own language, not
translated from the English.

After editing, regenerate the bundled copy:

```bash
./scripts/assemble-screenshot-fixtures.rb
```

It validates as it goes — a missing headline, an empty writing, a newline inside
a writing (the protocol writer rejects newlines), or a short archive column all
fail loudly rather than producing a thin screenshot.

Headlines use explicit `\n` line breaks so wrapping is a decision, not an
accident. The compositor shrinks the face a little if a localized line is too
wide, and refuses to render if a headline would collide with the app capture.

## The camera bubble

Scene 05 shows a still, not a live camera — a simulator has no camera, and a
webcam capture would not be reproducible. The image is
`assets/selfie-still.png`, mirrored into the asset catalog at build time.
**Replace that one file to change it.** A transparent PNG cutout gives the best
result, since that is how the real feature renders.

## Layout

Measured from the five original 1242 × 2688 screenshots and scaled to the
6.9-inch canvas by 1320/1242:

| | Reference | 6.9-inch |
|---|---|---|
| Background | `#F3D066` | same |
| Side margin | 178 | 189 |
| Headline top | 176 | 187 |
| Capture top | 545 | 579 |
| Capture width | 886 | 942 |
| Corner radius | ~0 (square) | 0 |

Headline face is **Noteworthy Bold**; Devanagari falls back to Kohinoor
Devanagari and Han to PingFang SC, because a Latin handwriting face has no
glyphs for those scripts and CoreText would otherwise substitute silently.
Override with `--font "Some Face"`.

## Useful flags

```bash
--locale es-MX        # one locale
--scene archive       # one scene
--skip-capture        # recompose from existing raw captures
--skip-build          # reuse the last build
--device "iPhone 16 Pro Max"
--font "Noteworthy Bold"
--keep-simulator      # leave it booted for inspection
```

## Directories

```
AppStoreScreenshots/
├── fixtures/     per-locale content (edit these)
├── assets/       the camera-bubble still
├── raw/          straight simulator captures
├── final/        upload-ready marketing frames
├── contact/      five-up sheets, one per locale, for visual QA
├── locales.json  generated locale manifest
└── manifest.json generated: every image, headline, dimension, alpha flag
```

`raw/`, `final/`, `contact/`, `manifest.json` and `locales.json` are generated.
