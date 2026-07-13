# WIRING — Lazure design system (WS5)

The lazure library lives in `app/src/main/java/inc/anky/android/ui/lazure/` and is
fully additive: nothing existing was touched, `ui/theme/AnkyTheme.kt` (dark-cosmic)
still drives every screen. This file is the retheme playbook for the phase that
consumes it.

## What exists

| Android (package `inc.anky.android.ui.lazure`) | iOS counterpart |
| --- | --- |
| `LazurePigments` (13 Display-P3 pigments + `hairline`) | `Color.anky*` in `AnkyLazure.swift` §1 |
| `LazureRoles` + `LocalLazureRoles` | `AnkyTheme` enum (`AnkyTheme.swift`) |
| `AnkyBreath`, `rememberBreathPhase()`, `LocalBreathClock` | `AnkyBreath` §2 + `TimelineView` drivers |
| `LazureWall(mood)`, `LazureMood.{Dawn,Dusk,Kingdom(Color)}` | `LazureWall` §3 (radial-wash path) |
| `Modifier.paperGrain()` / `PaperGrain()` / `LazureSeededRandom` | `PaperGrain` + `LazureSeededRandom` §4 |
| `VeilCard`, `LazureDivider` | `VeilCard`, `LazureDivider` §5 |
| `ThreadButton`, `WashButton` | `ThreadButtonStyle`, `WashButtonStyle` §6 |
| `LazureType` (ankyTitle/Heading/Prose/Label/Caption/Action) | `Font.anky*` §7 |
| `AnkySunGlyph` | `AnkySunGlyph` §8 |
| `VeiledFeature`, `ReflectionGhost` | §8.5 (phase-3 subscription veils) |
| `AnkyWritingFont`, `AnkyWritingTextSize`, `fontFamilyFor`, `writingTextStyle` | `AnkyWritingFontChoice` mapping §9 + `WritingPreferencesStore` enums |
| `WatercolorVeil(register)` | `WatercolorVeilView` |
| `AnkyverseDayPalette` | `AnkyverseDayPalette.swift` |
| `LevelTheme` (+ `colorFromHexSwatch`) | `LevelTheme.swift` |
| `LazureTheme { ... }` | MaterialTheme wrapper (new; iOS uses environment defaults) |
| `LazureGallery()` | debug-only QA sheet (no iOS counterpart) |

## How to retheme a screen

1. Wrap the screen (or the whole nav host, when everything is ready) in
   `LazureTheme { ... }` instead of `AnkyTheme { ... }`. It provides the
   Material3 paper/ink color scheme, lazure Material typography, the role
   tokens, and one shared breath clock for the subtree.
2. Replace the background with a full-screen `Box` whose first child is
   `LazureWall(mood)`:
   - default screens → `LazureMood.Dawn`
   - evening/ceremony surfaces → `LazureMood.Dusk`
   - painting-tinted screens → `LevelTheme.fromPalette(package.paletteHexes).wallMood`
3. Swap `AnkyPanel` → `VeilCard`, `AnkyActionButton` → `ThreadButton`
   (primary) / `WashButton` (secondary), `HorizontalDivider`/hand-rolled
   rules → `LazureDivider`.
4. Colors: reach for `LocalLazureRoles.current` (background/panel/border/
   text/textMuted/gold/success/danger) before raw `LazurePigments`. Never
   `Color.White`/`Color.Black`; hairlines are `LazurePigments.hairline`
   at 0.5dp; shadows stay violet (see `VeilCard` for the pattern).
5. Text: `LazureType.*` styles (serif for what is said, sans for chrome),
   colored with the roles. Material components under `LazureTheme` already
   pick up the remapped `Typography`.
6. Loading states: `WatercolorVeil(message = ..., register = Pale)` for
   gate/reflection waits, `Aubergine` over an ink background for the
   ceremony. No spinners, ever.
7. Subscription gating (phase 3): wrap the real UI in
   `VeiledFeature(surface = "reflection"|"ceremony"|"journey", message = <localized line>, onTap = { ... })`.
   The caller's `onTap` must do what iOS does inside the button: a light
   haptic and the `veil_tapped {surface}` funnel report, then open the
   paywall. Use `ReflectionGhost()` as the content when the reflection
   text may not be shown at all.
8. Writing surface: map the stored preference through
   `AnkyWritingFont.fromStoredValue(raw)` / `AnkyWritingTextSize.fromStoredValue(raw)`
   and build the style with `writingTextStyle(...)`, inked with
   `LazurePigments.ankyUmber` (the sepia pass). The lazure package
   deliberately does not import `core/storage/WritingPreferencesStore`;
   the storage layer should expose its raw string and call across.
   The stored raw values are the iOS ones: `quill|georgia|round|plain|typewriter`
   and `small|medium|large|grand`.
9. Write screen caveat (PARITY WS5): iOS keeps the writing chamber in its
   own darker treatment — check `WriteView` before retheming it; do not
   blanket-paper it.

## Window / manifest follow-ups (deliberately NOT done here)

- `Theme.Anky` window background & status/navigation bar colors should move
  from `#080713` to paper (`#F6EFE4` ≈ ankyPaper in sRGB) with dark status
  bar icons (`windowLightStatusBar=true`) once screens are papered —
  res edits were out of scope for WS5.
- `LazureGallery()` renders nothing in release builds. For visual QA, point
  a debug destination or an `@Preview` wrapper at it.

## Fidelity notes / approximations (vs. iOS)

- `LazureWall` ports the iOS 16/17 **radial-wash** path (4 drifting washes
  over paper), not the iOS 18 `MeshGradient`; iOS itself calls them "the
  same weather."
- Gradient fade-outs use same-hue `alpha = 0` colors instead of SwiftUI's
  `.clear` to avoid dark fringes in shader interpolation.
- `PaperGrain` rasterizes the identical seeded walk once into a
  1px-per-cell bitmap and draws it scaled with `FilterQuality.None` +
  `BlendMode.Multiply` (iOS re-runs its Canvas walk every frame).
- `VeilCard` replaces `.ultraThinMaterial` (live blur) with a translucent
  `ankyPaperDeep` underlay; violet shadow tint needs API 28+ (harmless
  plain shadow below).
- `ThreadButton`'s breathing gold glow is a capsule-hugging radial halo
  drawn behind the button (Android elevation shadows can't animate
  color/radius); alpha/spread arithmetic matches iOS (`0.25+0.15p`,
  `10+6p`, y+3).
- Reduce motion: iOS pauses its `TimelineView` when
  `accessibilityReduceMotion` is set; Android freezes the breath at 0.5
  when `ANIMATOR_DURATION_SCALE == 0` (animations off in system settings).
- Fonts: Android has no New York/Georgia/SF Rounded/American Typewriter.
  Quill & Georgia → system serif; Round → optional `sans-serif-rounded`
  device family (falls back to Roboto); Typewriter → optional
  `serif-monospace` (Cutive Mono on stock Android). Documented in
  `LazureTypography.kt` KDoc.
