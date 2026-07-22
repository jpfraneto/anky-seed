# Task: Apply Addendum 1.1 to the Axis Redesign

You are working in the Anky iOS monorepo. You have no memory of previous sessions — orient first:

1. Check out the `axis-redesign` branch (it exists on origin, 9 commits ahead of main).
2. Read `~/anky/docs/axis-redesign/SPEC.md` — the ratified spec a previous session built against.
3. Read `~/anky/docs/axis-redesign/PROGRESS.md` — what that session built: 7½ of 8 phases done, all behind `AppRoot.axisWorldEnabled = false`, all axis code in `apps/ios/Anky/Features/Axis/`.
4. Save this entire document as `~/anky/docs/axis-redesign/ADDENDUM-1.md`. It is ratified and authoritative: **where it conflicts with SPEC.md, this wins. Where it conflicts with the branch, the branch changes.**

Then implement sections A1–A4 below, and answer the verification questions. Working agreement:

- Everything stays behind the `axisWorldEnabled` flag. **Do NOT do Phase 8b** (no deletions of legacy screens, no router removal, no flag removal). 8b remains held until the loop is validated on a device.
- One commit per section (A1, A2, A3, A4), each compiled and screenshot-verified on the simulator before committing, matching the discipline of the previous session.
- Update PROGRESS.md when done: mark the addendum sections landed, and add a **`## Answers`** section responding to every verification question below. Where you cannot verify, say so — do not fill silence with defaults.

---

## A1. The Anchor gains a second context: surfacing — *retrofit to Phase 1/2*

The SPEC.md §2 grammar table is incomplete. On the landing surface, the Anchor's tap resolves by scroll position:

| Landing surface state | Tap |
|---|---|
| At rest at the top of the strata (the living edge) | Enter writing session |
| Scrolled away from the top (deep in memory) | **Surface to now** — return to the top of the column |
| An entry is open (§A2) | Close the entry, then surface |

- Surfacing is fast, slightly overshoots, settles at the newest entry. It should feel like coming up for air, not like `scrollTo(0)` with default animation.
- One tap, one meaning: after surfacing the user is at rest; a **second** tap opens the channel. Never chain them. Writing begins from a person who has arrived at now, not from momentum.
- "At rest at the top" has tolerance (~half a screen counts as top). No pixel-hunting.
- A writing session is never launched from deep in the strata.

State machine: add `landingAtTop` / `landingScrolled` / `entryOpen` as inputs to `AxisState`'s tap resolution.

## A2. The opened strata entry — exact geometry and order — *retrofit*

If the current full-entry read view is a pushed or presented screen, rebuild it as follows. "Tap an entry → opens to read in full" means, precisely:

1. **Decompress in place.** Tapping a stub expands it inline within the strata column; the neighboring strata are pushed apart. No pushed screen, no sheet, no modal, no navigation transition. The map never stops being a map.
2. **The day reopens in its original orientation:** the user's writing first, in full, at the top of the expanded region. Below it, after a quiet seam, Anky's reflection. The reflection is reached only by scrolling down through the user's own words — the order of the original day. There is no control, chip, tab, or affordance that displays the reflection directly. The reflection is never separately addressable.
3. **Closing:** while an entry is open, its date header pins to the top of the screen (sticky header). Tapping the pinned header compresses the day back into its stub; neighbors close around it.
4. **One entry open at a time.** Opening another seals the current one first.
5. The share/record affordances inherited from RevealView live inside the opened entry, placed after the reflection (bottom of the day), quiet, styled to the lazure register. `AnkyRecordingView` is reached from here. Nothing floats over the writing.

Landing gesture vocabulary, total: tap opens, tap closes, scroll moves through time, Anchor surfaces/writes. Nothing else exists.

## A3. Unsent sessions in the strata

Sessions that settle unsent (SPEC §4) coexist in the column with sent ones:

1. **The column does not visually distinguish sent from unsent.** No badge, no dimming, no icon, no "not sent" copy. The column is made only of presence; marking absence-of-reflection is a shame mechanic and violates doctrine.
2. **An opened unsent entry contains the writing only.** It ends where the writing ends. No placeholder, no empty-state copy, no prompt to send.
3. Retroactive sending (holding the Anchor inside an old unsent entry) is **out of scope for this release.** Do not build it, do not scaffold for it, do not leave dead code paths toward it.

## A4. Two voices within the lazure register — *SPEC §10 addition; retrofit to Phases 3, 5, and the opened entry*

Add a token pair inside the lazure register. The user's writing and Anky's reflection must read as two substances in one world:

- **Ore (the user's writing at rest):** Fraunces, regular, smaller optical size, tighter leading, ink slightly grayer/rawer than the current body text. Sediment. Applies to the sealed writing on the channel-closed screen and to the writing inside opened strata entries.
- **Glaze (Anky's reflection):** Fraunces italic OR a heavier/larger optical size — pick one treatment and apply it identically everywhere — more luminous ink, looser leading, more breathing room. Applies to the §6 reflection descent and to the reflection inside opened entries.
- The two voices are never labeled. No "You wrote" / "Anky said" copy anywhere. Typography alone carries the distinction.
- The live writing session keeps its current styling (it is the act, not the record). The vigil's traveling words keep the electric register's serif italic. Ore/glaze applies only within lazure, at rest.

Define both as named tokens in whatever type/token system the axis code uses, not as inline modifiers.

---

## Verification questions — answer in PROGRESS.md `## Answers`

1. **Free-vigil tracking:** where is first-vigil consumption stored? It must key to account identity (wallet address / RevenueCat appUserID), not the device, or a reinstall grants a second free vigil. If it is currently device-side, add a `TODO(server-reconcile)` and say so.
2. **Settle transition:** does Phase 6's `scrollTransition` implementation perform a true melt (the multi-line reflection geometrically interpolating into the one-line stub) or a crossfade at the scroll trigger? A disciplined crossfade is an acceptable compromise for this release — but state which one shipped.
3. **Anchor vs. keyboard avoidance:** confirm the AppRoot Anchor overlay ignores keyboard safe-area insets (`.ignoresSafeArea(.keyboard)` or equivalent) and that its absolute screen position is identical with keyboard up and down. The "keyboard covers the Anchor" story of SPEC §3 depends on this.
4. **Latency hiding:** confirm the reflection request fires at sentinel-close, and that a generated reflection for a session that is never sent is discarded or cached per the existing privacy posture — never attached to the entry as if it had been received.
5. **Accessibility vigil path:** SPEC §5 marks an alternate completion path (reduced hold or press-then-confirm under AssistiveTouch / Switch Control / reduced motion) as non-negotiable, but it appears in no completed phase. If it does not exist, implement it as part of this pass and note it; if it exists, say where.
6. **Surfacing performance:** after implementing A1, verify surface-to-now does not fire per-stratum `onAppear`/`scrollTransition` work for every entry it passes. Test with 500+ seeded entries and report.

---

## Ratified deviations — amend SPEC.md in the same pass

1. **Vigil is SwiftUI-native, not Rive.** Accepted. Amend SPEC §5 to remove the Rive requirement. Acceptance remains behavioral: seven escalating haptic detents ~1/sec, a distinct softer terminal beat, full visible drain on early release, charge monotonic with press duration.
2. Record in SPEC §7 whichever answer question 2 produced (melt vs. crossfade), so it is a known state, not a silent one.

When everything above is committed: update PROGRESS.md, push the branch, and stop. Do not begin 8b.
