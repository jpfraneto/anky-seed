# Minimal Write Controls

This lesson explains the small Write screen control pass.

## Mental model

The Write screen should feel like a chamber, not a toolbar. The top controls are escape hatches: one returns to the Map, and one imports a `.anky`. They should stay visually quiet.

## Files involved

- `Anky/Features/Write/WriteView.swift` owns the Write surface, the top action bar, and the sealed-day view.

## SwiftUI concepts

Both controls are plain `Button` views with `Image(systemName:)` labels. The visible UI is icon-only, but each button still has an `accessibilityLabel` so VoiceOver users hear the purpose.

The button keeps a `42x42` tap target. `WriteChromeIcon` gives that target a circular `.thinMaterial` background so it feels closer to the native navigation controls used elsewhere in the app, without adding text labels or heavier chrome.

## What changed

- The old `Map` text button became a circular `chevron.left` material button.
- The old `PASTE` text button became a circular `doc.on.clipboard` material button.
- The sealed-day controls use the same minimal icon treatment.

## Try this yourself

Run the app, enter Write, and check that the top-left control returns to Map while the top-right control still opens paste/import.
