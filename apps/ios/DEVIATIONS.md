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

<!-- Further deviations appended as implemented. -->
