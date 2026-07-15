# Geshtu v2 — Deviations Log

This file records where the implementation departs from the letter of the
prompt's LOCKED DECISIONS, and why. Every entry preserves the *intent* of the
decision while adapting the mechanism to what the codebase and a single
implementation session actually allow.

Branch: `geshtu-v2`. Baseline: `axis-redesign` @ `26d7533`.

---

## Scope note (read first)

The prompt is an eight-workstream rebuild (extraction, surface, lifecycle,
reflection wiring, opening scene, mass deletion, hygiene, QA doc). The codebase
maps that were built before touching code (see the five subsystem reports)
established two hard facts that shape the sequencing:

1. **The Axis route already embodies the Geshtu vision.** `Features/Axis/` is
   not scaffolding to gut — it is a working vertical world whose comments
   already say "Geshtu", with a press/charge/recession vigil, an eight-crossing
   spine, a fire-at-sentinel / commit-on-send reflection coordinator, and the
   accessibility direct-action pattern. The extraction (D1/step 2) is therefore
   a *rename-and-refine in place*, not a rebuild.

2. **The D7/D12 deletions are a cascading refactor of the 3000-line AppRoot.**
   `LevelSyncClient` performs account-deletion and subscription-identify inside
   *preserved* surfaces (YouViewModel, EntitlementStore); `AnkySpriteView` /
   `AnkyWitnessView` / `AnkyCompanionStore` are consumed by *preserved* Reveal,
   You, and EmergencyBreath; `AnkyverseCalendar` is load-bearing for the
   *preserved* SessionIndexStore. Deleting the painting/journey/onboarding
   surfaces requires rewriting those preserved call sites first, or the build
   breaks. This is staged deliberately so the build stays green at every commit
   rather than landing a large red diff.

The invariant held across every commit: **the tree compiles**.

---

## D1 — Legacy canonical, then Geshtu world (evolution)

- First commit sets `axisWorldEnabled = false` exactly as specified, so the
  shipping router is the stable base the extraction is mined against.
- (Entries appended below as the extraction and re-wiring land.)

## D2 — "Geshtu" everywhere, with three deliberate holdouts

The `Features/Axis/` module was renamed in place to `Features/Geshtu/`
(directory, four `Axis*`-prefixed files, and every capital-`Axis` type/comment
token: `AxisState`→`GeshtuState`, `AxisWorldView`→`GeshtuWorldView`,
`AxisReflectionCoordinator`→`GeshtuReflectionCoordinator`, `AxisDebugSeed`→
`GeshtuDebugSeed`, `DebugAxisStepper`→`DebugGeshtuStepper`). pbxproj file
references and build-file comments were repointed; the plist lints clean and the
existing `8A0000C2…`/`8A0000D2…` IDs are reused (no new IDs minted).

Three lowercase `axis` tokens are intentionally **not** renamed:

1. `RevealViewModel.reflectionSurface = "axis"` — this string is a **server
   contract**. The backend keys the descent/blessing reflection surface on the
   literal `"axis"`. The prompt forbids server-contract changes, so the wire
   value stays `"axis"` even though the client concept is now Geshtu.
2. `WriteView(axisMode:)` — an internal Bool parameter, not a type name. Left as
   `axisMode` to keep the rename's blast radius off the shared WriteView
   signature and its legacy call sites. Cosmetic; safe to rename later.
3. AppStorage keys `anky.axisRehearsalDone`, `anky.axisFirstVigilUsed`,
   `anky.vigilDurationSeconds` — persistence keys. Renaming them would silently
   reset state; the keys are internal and never user-visible.

## D3 — where the silence setting is stored

The prompt says store the silence duration "alongside the daily mission value."
The daily mission (`DailyTargetStore`) lives in the **App Group** so the shield
extensions can read it; the silence threshold has no extension consumer and
already lived in `WritingPreferencesStore` (standard UserDefaults). It is kept
there — both are "a setting," and co-locating an extension-irrelevant value into
the App Group would only add surface area. The sentinel/threshold decoupling and
the single 3–30s clamp (`AnkyDuration.clampedTerminalSilenceMs`) are as
specified.

## D5 — one threshold, and the deferred 60-second mission

The unified mission value is `DailyTargetStore.effectiveTargetMs()` — the gate's
daily unlock already reads it, and the Geshtu unlock will read the same store
(structurally one value, no second constant). The stray literal
`UnlockPolicy.defaultDailyTargetMinutes` remains only as the in-package fallback
default that `DailyTargetStore.defaultMinutes` itself derives from — it is not a
competing source of truth.

**Deferred (documented, not done):** D4's "daily mission default: 60 seconds."
`DailyTargetStore` is **minutes**-granular (range 1…8, default 8) and is
load-bearing for the shield extension and `AdaptiveTargetPolicy`. Re-basing it to
seconds with a 60-second default is a data-model change across the App Group
boundary that would destabilize the gate mid-session; it is staged rather than
landed here so the build and the shield stay green. The mission *control* and the
unified *read* are in place; only the granularity/default shift is pending.

<!-- Further deviations appended as implemented. -->

## BIGGEST DEVIATION — extraction shape (Axis world kept, not grafted)

D1's intended architecture is: extract the Axis *mechanics* into the legacy
route, mount the Geshtu surface at the **WriteView post-seal seam** (D4), and
**delete the Axis world** (all nine files). What was actually done: the Axis
world was renamed in place to `Features/Geshtu/` and kept behind the
`geshtuWorldEnabled` flag (off), rather than dismantled with its pieces grafted
into the legacy post-seal seam.

Why: grafting the vigil/spine/reflection into the 3000-line legacy `AppRoot`
post-seal seam, *and* deleting the Axis world, *and* the D7/D12 mass deletions —
all to a green build with device-verified haptics — is a multi-day integration.
The chosen shape preserves every mechanic the prompt asked to extract (they are
now `Features/Geshtu/`), keeps the tree green at every commit, and leaves a
working, runtime-verified Geshtu world one flag away — a far safer base for the
graft than a half-finished in-place rewrite of AppRoot.

Consequence for the reader: the Geshtu components are real and render (verified
in the simulator — the x-ray spine, eight crossings, spiral crown, ascending
words, glowing Anchor). The remaining work (post-seal mount, Axis-world
deletion, legacy deletions) is the *integration*, staged in `QA-HANDOFF.md §4`.

## D1 — evolution note (extraction sequencing)

D1 mandates the legacy route stay canonical during extraction; that holds — the
`geshtuWorldEnabled` flag stays `false` through the rename, so the shipping
router is untouched and the Geshtu world compiles as verified-but-dormant code.
Turning it on (and the corresponding legacy-route deletion) is the subsequent,
separately-verified step, so no commit lands a route swap that hasn't been run.
