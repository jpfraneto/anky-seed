# Disabling The Ritual Onboarding

This lesson explains the rollback that removed the first-run ritual trailer and restored Anky's original companion rendering.

## Mental model

The app should now open directly into the main tab flow again. `AppRoot` owns that decision: it builds the `TabView`, shows the Face ID lock when needed, and keeps the small Anky presence overlay on top.

The onboarding trailer used to be another full-screen layer in `AppRoot`. Removing that layer means the app no longer blocks Write behind a staged explanation flow.

## Files involved

- `Anky/AppRoot.swift` no longer tracks onboarding presentation state and no longer presents `RitualOnboardingView`.
- `Anky/Features/You/YouView.swift` no longer shows the ritual trailer replay row.
- `Anky/Support/AnkySpriteView.swift` is back to the original asset-catalog frame renderer.
- `Anky/Support/AnkyWitnessView.swift` again shows the animated sprite only for the main companion size; smaller witness placements use the quiet glyph.
- `Anky/Features/Write/WriteView.swift` and `Anky/Features/Reveal/RevealView.swift` use legacy animation names instead of generated onboarding rows.

## SwiftUI concepts

SwiftUI layers are just conditional views. The onboarding was noisy because it was a high-priority conditional layer above the tab app. Removing that condition returns control to the normal `TabView`.

The companion rendering now uses the existing asset catalog images through `Image(frameName)`. That is simpler than loading a JSON manifest, decoding PNG strips, and cropping frames at runtime.

## Why this is safer

The generated onboarding pack added many new moving parts: bundled resources, `pet.json`, custom frame cropping, and extra animation mappings. Since the visual direction did not work, removing those parts reduces bundle size and keeps Anky visually consistent with the rest of the app.

## Try this yourself

Run the app and confirm it opens directly to Write after unlock. Then switch between Write, Map, and You and watch the small Anky overlay use the original simple animations.
