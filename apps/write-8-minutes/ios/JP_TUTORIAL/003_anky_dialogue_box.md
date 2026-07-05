# Anky Dialogue Box

This lesson explains the native dialogue-box pattern used when the app speaks to the writer.

## Mental model

App messages should not feel like generic alerts. In Anky, the companion is the speaker. The UI should make that relationship obvious: Anky appears beside a text box, and the message is visually framed as dialogue.

## Files involved

- `Anky/Support/AnkyWitnessView.swift` defines `AnkyCompanionPromptView`, the shared dialogue component.
- `Anky/Features/Write/WriteView.swift` uses the dialogue for writing/import errors.
- `Anky/Features/Reveal/RevealView.swift` uses the dialogue for reflection prompts and errors.
- `Anky/Features/You/YouView.swift` now uses the dialogue for status and error messages.

## SwiftUI concepts

The dialogue component is still plain SwiftUI. It combines:

- `AnkyWitnessView` as the speaker.
- A dark rounded rectangle as the dialogue panel.
- A double stroke to evoke an RPG dialogue box without importing new art.
- Text-only action buttons, avoiding decorative symbols.

The call sites did not need a new architecture. They still pass `state`, `message`, and optional action data into `AnkyCompanionPromptView`.

## Why this matters

This keeps communication consistent. If the app cannot open an artifact, has a status update, or offers reflection, the user sees Anky delivering that message instead of seeing a random system card.

## Try this yourself

Trigger a bad `.anky` paste, then open You after changing a setting. Both messages should now feel like Anky is speaking from the same dialogue system.
